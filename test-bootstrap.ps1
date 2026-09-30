# test-bootstrap.ps1 - Assert-based test for bootstrap script
$ErrorActionPreference = "Stop"

$tempDir = Join-Path $env:TEMP ("omp-test-" + [System.Guid]::NewGuid().ToString("N"))
try {
    $env:AI_BASE_URL = "https://test.local"
    $env:AI_API_KEY = "test-key-abc"
    $env:JIRA_URL = "https://test.jira"
    $env:JIRA_PERSONAL_TOKEN = "test-jira-token"
    $env:CONFLUENCE_URL = "https://test.conf"
    $env:CONFLUENCE_PERSONAL_TOKEN = "test-conf-token"
    $env:CONTEXT7_API_KEY = "test-ctx-token"
    Write-Host "Running bootstrap into temp dir: $tempDir"
    & "$PSScriptRoot\bootstrap.ps1" -DryRun:$false -SkipInstall -OmpDir $tempDir
    # Assert all 3 config files are generated
    foreach ($file in @("mcp.json", "models.yml", "config.yml")) {
        $path = Join-Path $tempDir $file
        if (-not (Test-Path $path)) {
            throw "ASSERTION FAILED: Missing generated file: $path"
        }
        $len = (Get-Item $path).Length
        if ($len -le 0) {
            throw "ASSERTION FAILED: Empty file: $path"
        }
    }

    # Assert mcp.json contains valid gitnexus, company-atlassian with pinned version, and no dead $schema
    $mcpRaw = Get-Content (Join-Path $tempDir "mcp.json") -Raw
    if ($mcpRaw.Contains('"$schema"')) {
        throw "ASSERTION FAILED: mcp.json contains dead 404 `$schema reference"
    }
    $mcpJson = $mcpRaw | ConvertFrom-Json
    if ($mcpJson.mcpServers.gitnexus.command -ne "cmd") {
        throw "ASSERTION FAILED: gitnexus command should be 'cmd', found: $($mcpJson.mcpServers.gitnexus.command)"
    }
    if ($mcpJson.mcpServers.'company-atlassian'.command -ne "uvx") {
        throw "ASSERTION FAILED: company-atlassian command should be 'uvx'"
    }
    if ($mcpJson.mcpServers.'company-atlassian'.args[0] -ne "--from" -or $mcpJson.mcpServers.'company-atlassian'.args[1] -notlike "mcp-atlassian==*") {
        throw "ASSERTION FAILED: company-atlassian should pin version via --from mcp-atlassian==..."
    }
    if (-not $mcpJson.mcpServers.context7) {
        throw "ASSERTION FAILED: context7 missing in mcp.json"
    }
    # Assert models.yml interpolated env var
    $modelsYml = Get-Content (Join-Path $tempDir "models.yml") -Raw
    if (-not $modelsYml.Contains("apiKey: test-key-abc")) {
        throw "ASSERTION FAILED: models.yml did not interpolate AI_API_KEY"
    }

    # Assert UV_CACHE_DIR is expanded without literal placeholders
    $mcpRaw = Get-Content (Join-Path $tempDir "mcp.json") -Raw
    if ($mcpRaw.Contains("__UV_CACHE_DIR__") -or $mcpRaw.Contains('${USERPROFILE}')) {
        throw "ASSERTION FAILED: mcp.json contains unexpanded UV_CACHE_DIR placeholder"
    }

    # Assert config.yml contains full task routing
    $configRaw = Get-Content (Join-Path $tempDir "config.yml") -Raw
    if (-not $configRaw.Contains("agentModelOverrides:") -or -not $configRaw.Contains("autoqaConsent: granted")) {
        throw "ASSERTION FAILED: config.yml missing task routing or dev flags"
    }

    # Assert copied static files
    foreach ($mdFile in @("AGENTS.md", "RULES.md", "SYSTEM.md")) {
        $path = Join-Path $tempDir $mdFile
        if (-not (Test-Path $path)) {
            throw "ASSERTION FAILED: Missing copied file: $path"
        }
    }
    $skillsDir = Join-Path $tempDir "skills"
    if (-not (Test-Path $skillsDir)) {
        throw "ASSERTION FAILED: Missing copied skills/ directory: $skillsDir"
    }
    $skillFiles = Get-ChildItem -Path $skillsDir -Recurse -Filter "SKILL.md"
    if ($skillFiles.Count -eq 0) {
        throw "ASSERTION FAILED: No SKILL.md found in copied skills/ directory"
    }

    Write-Host "TEST PASSED: bootstrap created valid configs." -ForegroundColor Green
}
finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
}