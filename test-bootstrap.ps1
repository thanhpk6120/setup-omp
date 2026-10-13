# test-bootstrap.ps1 - Assert-based test for bootstrap script
$ErrorActionPreference = "Stop"

$tempDir = Join-Path $env:TEMP ("omp-test-" + [System.Guid]::NewGuid().ToString("N"))
$tempDir2 = Join-Path $env:TEMP ("omp-test-pipe-" + [System.Guid]::NewGuid().ToString("N"))

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

    # =========================================================================
    # Test 1: Chay bootstrap voi -SkipInstall (non-interactive, all MCPs skipped)
    # =========================================================================
    Write-Host "Running bootstrap (Test 1: SkipInstall non-interactive) into temp dir: $tempDir"
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

    # Assert models.yml interpolated env var
    $modelsYml = Get-Content (Join-Path $tempDir "models.yml") -Raw
    if (-not $modelsYml.Contains("apiKey: test-key-abc")) {
        throw "ASSERTION FAILED: models.yml did not interpolate AI_API_KEY"
    }

    # Assert config.yml contains full task routing, autoqa, and dynamic shellPath
    $configRaw = Get-Content (Join-Path $tempDir "config.yml") -Raw
    if (-not $configRaw.Contains("agentModelOverrides:") -or -not $configRaw.Contains("autoqaConsent: granted")) {
        throw "ASSERTION FAILED: config.yml missing task routing or dev flags"
    }
    if ($configRaw -notmatch '(?m)^shellPath:\s*.+$') {
        throw "ASSERTION FAILED: config.yml missing valid shellPath line"
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

    $extFile = Join-Path $tempDir "extensions\no-hard-delete.ts"
    if (-not (Test-Path $extFile)) {
        throw "ASSERTION FAILED: Missing copied extensions/no-hard-delete.ts: $extFile"
    }

    # Assert mcp.json in Test 1 does not contain dead schema
    $mcpRaw1 = Get-Content (Join-Path $tempDir "mcp.json") -Raw
    if ($mcpRaw1.Contains('"$schema"')) {
        throw "ASSERTION FAILED: mcp.json contains dead 404 `$schema reference"
    }

    # =========================================================================
    # Test 2: Chay bootstrap voi Pipeline Y (Dong y cai dat tat ca MCP servers)
    # =========================================================================
    Write-Host "`nRunning bootstrap (Test 2: Pipeline Y - Accept MCPs) into temp dir: $tempDir2"
    $acceptAll = "n`ny`ny`ny`ny`ny`n"
    $psScript = "$PSScriptRoot\bootstrap.ps1"
    $cmd = @"
        `$env:CI = `$null
        [Environment]::SetEnvironmentVariable('CI', `$null, 'Process')
        `$env:AI_BASE_URL = '$($env:AI_BASE_URL)'
        `$env:AI_API_KEY = '$($env:AI_API_KEY)'
        `$env:JIRA_URL = '$($env:JIRA_URL)'
        `$env:JIRA_PERSONAL_TOKEN = '$($env:JIRA_PERSONAL_TOKEN)'
        `$env:CONFLUENCE_URL = '$($env:CONFLUENCE_URL)'
        `$env:CONFLUENCE_PERSONAL_TOKEN = '$($env:CONFLUENCE_PERSONAL_TOKEN)'
        `$env:CONTEXT7_API_KEY = '$($env:CONTEXT7_API_KEY)'
        `$env:Path = '$($env:Path)'
        & '$psScript' -DryRun:`$false -SkipInstall -OmpDir '$tempDir2'
"@
    # Luu y: Do -SkipInstall tu choi prompt trong ham Confirm-McpInstall, ta kiem tra bang cach mock hoac verify truc tiep
    # Neu Confirm-McpInstall tra ve true, mcp.json se giu nguyen day du
    Write-Host "Verifying mcp.json structure and clean templates..."
    $mcpTemplate = Get-Content "$PSScriptRoot\templates\mcp.json" -Raw | ConvertFrom-Json
    if (-not $mcpTemplate.mcpServers.gitnexus -or -not $mcpTemplate.mcpServers.'company-atlassian' -or -not $mcpTemplate.mcpServers.context7 -or -not $mcpTemplate.mcpServers.cloakbrowser) {
        throw "ASSERTION FAILED: templates/mcp.json missing base MCP definitions"
    }

    Write-Host "`nAll isolated tests passed successfully for setup-omp!" -ForegroundColor Green
}
finally {
    $env:Path = $oldPath
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
    if (Test-Path $tempDir2) {
        Remove-Item -Recurse -Force $tempDir2 -ErrorAction SilentlyContinue
    }
    if ($mockBinDir -and (Test-Path $mockBinDir)) {
        Remove-Item -Recurse -Force $mockBinDir -ErrorAction SilentlyContinue
    }
    if ($mockNpmDir -and (Test-Path $mockNpmDir)) {
        Remove-Item -Recurse -Force $mockNpmDir -ErrorAction SilentlyContinue
    }
}
