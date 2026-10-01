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

# Setup mock environment for gitnexus and context7 to ensure test succeeds in clean environment
$mockBinDir = Join-Path $env:TEMP ("omp-mock-bin-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $mockBinDir | Out-Null
Set-Content -Path (Join-Path $mockBinDir "gitnexus.cmd") -Value "@echo off`necho gitnexus"
$oldPath = $env:Path
$env:Path = "$mockBinDir;$env:Path"

$mockNpmDir = Join-Path $env:TEMP ("omp-mock-npm-" + [System.Guid]::NewGuid().ToString("N"))
$mockContext7Path = Join-Path $mockNpmDir "@upstash\context7-mcp\dist"
New-Item -ItemType Directory -Force -Path $mockContext7Path | Out-Null
Set-Content -Path (Join-Path $mockContext7Path "index.js") -Value "// mock"

function global:npm {
    param([Parameter(ValueFromRemainingArguments)]$remaining)
    if ($remaining -contains "root" -and $remaining -contains "-g") {
        return $mockNpmDir
    }
    $realNpm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($realNpm) {
        & $realNpm @remaining
    }
}

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
    if ($mcpJson.mcpServers.'company-atlassian'.command -ne "mcp-atlassian") {
        throw "ASSERTION FAILED: company-atlassian command should be 'mcp-atlassian'"
    }
    if ($mcpJson.mcpServers.'company-atlassian'.args -contains "--from") {
        throw "ASSERTION FAILED: company-atlassian should not use --from"
    }
    if (-not $mcpJson.mcpServers.context7) {
        throw "ASSERTION FAILED: context7 missing in mcp.json"
    }
    if ($mcpJson.mcpServers.context7.command -ne "node") {
        throw "ASSERTION FAILED: context7 command should be 'node'"
    }
    if ($mcpRaw -match '["\'']npx["\'']') {
        throw "ASSERTION FAILED: mcp.json should not contain any npx fallback"
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
    $env:Path = $oldPath
    if ($mockBinDir -and (Test-Path $mockBinDir)) { Remove-Item -Recurse -Force $mockBinDir -ErrorAction SilentlyContinue }
    if ($mockNpmDir -and (Test-Path $mockNpmDir)) { Remove-Item -Recurse -Force $mockNpmDir -ErrorAction SilentlyContinue }
    Remove-Item function:global:npm -ErrorAction SilentlyContinue

    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
}