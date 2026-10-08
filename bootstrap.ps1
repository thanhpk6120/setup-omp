# bootstrap.ps1 - Bootstrap .omp environment on fresh machine
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [switch]$Force,
    [switch]$OverwriteAll,
    [switch]$EnableMemorix,
    [switch]$DisableMemorix,
    [string]$OmpDir = "$env:USERPROFILE\.omp\agent"
)

if (-not $PSBoundParameters.ContainsKey('EnableMemorix') -and -not $PSBoundParameters.ContainsKey('DisableMemorix')) {
    $memorixCmd = Get-Command "memorix" -ErrorAction SilentlyContinue
    if ($memorixCmd) {
        Write-Host "==> Đã phát hiện Memorix trên hệ thống tại: $($memorixCmd.Source)" -ForegroundColor Green
        Write-Host "    -> Tự động kích hoạt và cập nhật Memorix lên phiên bản mới nhất..." -ForegroundColor Cyan
        $EnableMemorix = $true
    } else {
        $memorixChoice = Read-Host "Bạn có muốn cài đặt Memorix (MCP & Session Memory) không? [y/N]"
        $EnableMemorix = if (-not [string]::IsNullOrWhiteSpace($memorixChoice) -and $memorixChoice.Trim().ToLower() -eq 'y') { $true } else { $false }
    }
} elseif ($DisableMemorix.IsPresent) {
    $EnableMemorix = $false
} else {
    $EnableMemorix = $EnableMemorix.IsPresent
}

$isForce = $Force.IsPresent -or $OverwriteAll.IsPresent

$ErrorActionPreference = "Stop"

Write-Host "==> Checking runtime dependencies..." -ForegroundColor Cyan
foreach ($tool in @("node", "npm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing '$tool' in PATH. Please install it first."
    }
}

# MCP tools (context7, gitnexus) require Node >= 22.18.0.
$nodeVerRaw = (node -v 2>$null | Out-String).Trim()
try {
    $nodeVer = [version]($nodeVerRaw.TrimStart('v'))
} catch {
    throw "Không thể xác định version của Node.js: '$nodeVerRaw'"
}
if ($nodeVer -lt [version]"22.18.0") {
    $toolsList = "gitnexus, context7"
    if ($EnableMemorix) { $toolsList = "memorix, gitnexus, context7" }
    throw "Yêu cầu Node.js >= 22.18.0 (do $toolsList yêu cầu Node.js mới). Phiên bản hiện tại: '$nodeVerRaw'. Vui lòng nâng cấp Node.js."
}

# uv / uvx (required by company-atlassian MCP)
if (-not $SkipInstall -and -not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Host "==> 'uv' not found. Installing uv..." -ForegroundColor Cyan
    if (-not $DryRun) {
        $installed = $false
        if (Get-Command "pip" -ErrorAction SilentlyContinue) {
            try {
                pip install uv --quiet
                $installed = $true
            } catch {}
        }
        if (-not $installed -and (Get-Command "winget" -ErrorAction SilentlyContinue)) {
            try {
                winget install --id=astral-sh.uv -e --silent --accept-source-agreements --accept-package-agreements
                $installed = $true
            } catch {}
        }
        if (-not $installed) {
            try {
                irm https://astral.sh/uv/install.ps1 | iex
                $env:Path = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:Path"
            } catch {
                Write-Warning "Could not install uv automatically. Please install it manually: https://docs.astral.sh/uv/"
            }
        }
    }
}
if (-not $SkipInstall) {
    Write-Host "==> Installing/updating mcp-atlassian globally via uv tool..." -ForegroundColor Cyan
    if (-not $DryRun) {
        if (Get-Command "uv" -ErrorAction SilentlyContinue) {
            try {
                uv tool install mcp-atlassian==0.23.1 --upgrade
            } catch {
                Write-Warning "Failed to install mcp-atlassian via uv: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "'uv' is not available. Please install 'mcp-atlassian' manually: uv tool install mcp-atlassian==0.23.1"
        }
    }
}



# gitnexus: vendor recommends a global install + absolute-path config to avoid npx
# (https://github.com/abhigyanpatwari/GitNexus README, "Fastest MCP startup").
if (-not $SkipInstall) {
    Write-Host "==> Installing gitnexus globally..." -ForegroundColor Cyan
    if (-not $DryRun) {
        npm install -g gitnexus --silent
    }
}

$gn = Get-Command "gitnexus" -ErrorAction SilentlyContinue
if ($gn -and $gn.Source) {
    $absGn = ($gn.Source).Replace('\', '\\')
    $gitnexusArgsJson = '"/c", "' + $absGn + '", "mcp"'
} else {
    throw "Lỗi: Không tìm thấy gitnexus bằng Get-Command. Dừng cài đặt."
}

$context7Command = '"node"'
if (-not $SkipInstall) {
    Write-Host "==> Installing context7 globally..." -ForegroundColor Cyan
    if (-not $DryRun) {
        npm install -g @upstash/context7-mcp --silent
    }
}

if (-not $SkipInstall -and -not (Get-Command "glab" -ErrorAction SilentlyContinue)) {
    Write-Host "==> Installing glab (GitLab CLI) globally..." -ForegroundColor Cyan
    if (-not $DryRun) {
        if (Get-Command "winget" -ErrorAction SilentlyContinue) {
            try {
                winget install -e --id GLab.GLab --silent --accept-source-agreements --accept-package-agreements | Out-Null
                $glabProg = "$env:LOCALAPPDATA\Programs\glab"
                if (Test-Path $glabProg) {
                    $env:Path = "$glabProg;$env:Path"
                }
            } catch {
                Write-Warning "Failed to install glab via winget: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "'winget' is not available. Please install glab manually."
        }
    }
}

if ($EnableMemorix) {
    if (-not $SkipInstall) {
        Write-Host "==> Installing memorix globally..." -ForegroundColor Cyan
        if (-not $DryRun) {
            npm install -g memorix
        }
    }
    Write-Host "==> Configuring memorix hook for omp..." -ForegroundColor Cyan
    if (-not $DryRun) {
        $npmPrefix = ""
        try { $npmPrefix = (npm prefix -g 2>$null | Out-String).Trim() } catch {}
        if ($npmPrefix -and (Test-Path $npmPrefix) -and ($env:Path -notlike "*$npmPrefix*")) {
            $env:Path = "$npmPrefix;$env:Path"
        }
        try {
            memorix setup --agent omp --global
        } catch {
            Write-Warning "Không thể chạy hook 'memorix setup --agent omp --global': $($_.Exception.Message)"
        }
    }
}

$npmRoot2 = ""
try {
    $npmRoot2 = (npm root -g 2>$null) | Out-String
    $npmRoot2 = $npmRoot2.Trim()
} catch {}

if ($npmRoot2) {
    $ctxP2 = Join-Path $npmRoot2 "@upstash\context7-mcp\dist\index.js"
    if (Test-Path $ctxP2) {
        $absCtx2 = ($ctxP2).Replace('\', '\\')
        $context7ArgsJson = '"' + $absCtx2 + '"'
    } else {
        throw "Lỗi: Không tìm thấy file dist\index.js của context7. Dừng cài đặt."
    }
} else {
    throw "Lỗi: Không tìm thấy thư mục npm root -g để lấy đường dẫn context7. Dừng cài đặt."
}
Write-Host "==> Ensuring directory $OmpDir exists..." -ForegroundColor Cyan
if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $OmpDir | Out-Null
}

# MCP template — docs:
#   gitnexus:          https://github.com/abhigyanpatwari/GitNexus (global install + absolute path avoids npx cold-start timeout)
#   mcp-atlassian:     https://mcp-atlassian.soomiles.com/docs/installation (pinned via uvx --from)
#   context7:          https://github.com/upstash/context7 (optional CONTEXT7_API_KEY for higher rate limits)
$mcpTemplate = @'
{
  "mcpServers": {
    "gitnexus": {
      "command": "cmd",
      "args": [__GITNEXUS_ARGS__]
    },
    "company-atlassian": {
      "command": "mcp-atlassian",
      "args": [],
      "env": {
        "JIRA_URL": "__JIRA_URL__",
        "JIRA_PERSONAL_TOKEN": "__JIRA_PERSONAL_TOKEN__",
        "CONFLUENCE_URL": "__CONFLUENCE_URL__",
        "CONFLUENCE_PERSONAL_TOKEN": "__CONFLUENCE_PERSONAL_TOKEN__",
        "TOOLSETS": "default"
      }
    },
    "context7": {
      "command": __CONTEXT7_CMD__,
      "args": [__CONTEXT7_ARGS__],
      "env": {
        "CONTEXT7_API_KEY": "__CONTEXT7_API_KEY__"
      }
    },
    "glab": {
      "command": "glab",
      "args": [
        "mcp",
        "serve"
      ]
    },
    "cloakbrowser": {
      "command": "node",
      "args": [
        "__CLOAKBROWSER_SCRIPT__"
      ]
    }
  }
}
'@

$modelsTemplate = @'
providers:
  9router:
    baseUrl: __AI_BASE_URL__
    api: openai-completions
    apiKey: __AI_API_KEY__
    compat:
      supportsDeveloperRole: true
      supportsReasoningEffort: true
      disableReasoningOnToolChoice: true
    models:
      - id: claude-fable-5
        contextWindow: 1000000
      - id: claude-opus-5
        contextWindow: 1000000
      - id: claude-sonnet-5
        contextWindow: 1000000
      - id: claude-haiku-4-5-20251001
        contextPromotionTarget: claude-sonnet-5
    disableStrictTools: true
'@

$configTemplate = @'
shellPath: C:\Program Files\Git\bin\bash.exe
symbolPreset: unicode
composer:
  shape: claude
theme:
  dark: titanium
  light: light
setupVersion: 2
modelRoles:
  default: 9router/claude-sonnet-5:medium
  smol: 9router/claude-sonnet-5:medium
  slow: 9router/claude-opus-5:xhigh
  vision: 9router/claude-sonnet-5:medium
  plan: 9router/claude-opus-5:high
  designer: 9router/claude-sonnet-5:medium
  commit: 9router/claude-sonnet-5:medium
  tiny: 9router/claude-haiku-4-5-20251001
  task: 9router/claude-sonnet-5:medium
  advisor: 9router/claude-opus-5:xhigh
computer:
  enabled: true
task:
  agentModelOverrides:
    task: 9router/claude-opus-5:medium
    scout: 9router/claude-sonnet-5:medium
    sonic: 9router/claude-sonnet-5:medium
    docs-fact-check: 9router/claude-opus-5:high
    docs-reviewer: 9router/claude-opus-5:medium
    docs-init: 9router/claude-opus-5:medium
    docs-update: 9router/claude-opus-5:medium
    docs-reader: 9router/claude-sonnet-5:medium
    architect: 9router/claude-opus-5:medium
    plan-reviewer: 9router/claude-opus-5:medium
    reviewer: 9router/claude-opus-5:medium
    security-reviewer: 9router/claude-opus-5:high
    dely-implementer: 9router/claude-sonnet-5:medium
    dely-reviewer: 9router/claude-opus-5:high
  eager: always
  batch: true
  maxConcurrency: 16
  maxRecursionDepth: 2
  agentAdvisor:
    task: "on"
    scout: "on"
    sonic: "on"
    docs-fact-check: "on"
    docs-reviewer: "on"
    docs-init: "on"
    docs-update: "on"
    docs-reader: "on"
    architect: "on"
    plan-reviewer: "on"
    reviewer: "on"
    security-reviewer: "on"
    dely-implementer: "on"
    dely-reviewer: "on"
  agentPrewalk:
    task: "on"
    scout: "on"
    sonic: "on"
    docs-fact-check: "on"
    docs-reviewer: "on"
    docs-init: "on"
    docs-update: "on"
    docs-reader: "on"
    architect: "on"
    plan-reviewer: "on"
    reviewer: "on"
    security-reviewer: "on"
    dely-implementer: "on"
    dely-reviewer: "on"
snapcompact:
  systemPrompt: agents-md,rules-md
dev:
  autoqaConsent: granted
'@

Write-Host "==> Preparing configuration files..." -ForegroundColor Cyan
function Load-Env {
    param([string]$EnvPath = (Join-Path $PSScriptRoot ".env"))
    if (Test-Path $EnvPath) {
        Write-Host "  -> Loading environment from $EnvPath..." -ForegroundColor Cyan
        Get-Content $EnvPath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#")) {
                $idx = $line.IndexOf("=")
                if ($idx -gt 0) {
                    $key = $line.Substring(0, $idx).Trim()
                    $val = $line.Substring($idx + 1).Trim()
                    if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                        $val = $val.Substring(1, $val.Length - 2)
                    }
                    if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($val)) {
                        [Environment]::SetEnvironmentVariable($key, $val, "Process")
                    }
                }
            }
        }
    }
}
Load-Env

function Get-CloakBrowserInstallDir {
    param([string]$EnvVarName = "CLOAKBROWSER_DIR")
    $envVal = [Environment]::GetEnvironmentVariable($EnvVarName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($envVal)) { return $envVal.Trim() }
    
    $drives = @()
    try {
        $drives = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 3 } | Sort-Object FreeSpace -Descending
    } catch {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -gt 0 } | Sort-Object Free -Descending
    }
    if (-not $drives -or $drives.Count -eq 0) { return "$env:USERPROFILE\mcp-servers\cloakbrowser" }

    $defaultDrive = $drives | Where-Object { ($_.DeviceID -eq 'D:' -or $_.Name -eq 'D') } | Select-Object -First 1
    if (-not $defaultDrive) { $defaultDrive = $drives[0] }
    $defaultLetter = ""
    if ($defaultDrive.DeviceID) { $defaultLetter = $defaultDrive.DeviceID } else { $defaultLetter = "$($defaultDrive.Name):" }
    if ([Environment]::GetEnvironmentVariable("CI") -or -not [Environment]::UserInteractive) {
        return "$defaultLetter\mcp-servers\cloakbrowser"
    }

    Write-Host "`n==> Quet danh sach o dia (Local Drives) de cai dat CloakBrowser MCP:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $devId = ""
        if ($d.DeviceID) { $devId = $d.DeviceID } else { $devId = "$($d.Name):" }
        $volName = ""
        if ($d.VolumeName) { $volName = " ($($d.VolumeName))" }
        $freeGB = 0
        if ($d.FreeSpace) { $freeGB = [math]::Round(($d.FreeSpace / 1GB), 2) } elseif ($d.Free) { $freeGB = [math]::Round(($d.Free / 1GB), 2) }
        $sizeGB = "N/A"
        if ($d.Size) { $sizeGB = [math]::Round(($d.Size / 1GB), 2) }
        Write-Host "  [$($i+1)] O $devId$volName | Trong: $freeGB GB / $sizeGB GB"
    }

    $promptMsg = "Chon so thu tu o dia muon luu CloakBrowser (mac dinh o $defaultLetter)"
    try {
        $inputVal = Read-Host $promptMsg
        if (-not [string]::IsNullOrWhiteSpace($inputVal)) {
            $choice = $inputVal.Trim()
            $idx = 0
            if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $drives.Count) {
                $chosen = $drives[$idx - 1]
                $chosenLetter = ""
                if ($chosen.DeviceID) { $chosenLetter = $chosen.DeviceID } else { $chosenLetter = "$($chosen.Name):" }
                return "$chosenLetter\mcp-servers\cloakbrowser"
            }
        }
    } catch {}
    return "$defaultLetter\mcp-servers\cloakbrowser"
}

function Setup-CloakBrowser {
    param([string]$TargetDir, [string]$SourceDir, [switch]$DryRun, [switch]$SkipInstall)
    Write-Host "==> Cau hinh CloakBrowser tai: $TargetDir" -ForegroundColor Cyan
    if (-not (Test-Path $TargetDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
    }

    $mainScript = Join-Path $TargetDir "mcp-server-full.mjs"
    $pkgJson = Join-Path $TargetDir "package.json"
    if ((Test-Path $mainScript) -and (Test-Path $pkgJson)) {
        Write-Host "  -> CloakBrowser da ton tai day du file ma nguon. Giu nguyen du lieu & profile cu (khong ghi de)." -ForegroundColor Green
    } else {
        Write-Host "  -> Copy ma nguon CloakBrowser sang $TargetDir..." -ForegroundColor Green
        if (-not $DryRun -and (Test-Path $SourceDir)) {
            Copy-Item -Path "$SourceDir\*" -Destination $TargetDir -Recurse -Force
        }
    }

    $nodeModules = Join-Path $TargetDir "node_modules"
    if (-not $SkipInstall -and -not (Test-Path $nodeModules)) {
        Write-Host "  -> Dang chay 'npm install' cho CloakBrowser..." -ForegroundColor Cyan
        if (-not $DryRun) {
            Push-Location $TargetDir
            try { npm install --omit=dev --silent } catch { Write-Warning "npm install cho CloakBrowser gap loi: $($_.Exception.Message)" } finally { Pop-Location }
        }
    }
    return $mainScript
}

function Setup-TrashGuard {
    param(
        [string]$OmpDir = "$env:USERPROFILE\.omp\agent",
        [switch]$DryRun,
        [switch]$SkipInstall
    )
    Write-Host "==> Cai dat Trash Guard (bao ve chan xoa cung cho OMP)..." -ForegroundColor Cyan

    # Cai dat OMP Extension (no-hard-delete.ts) vao OmpDir va ~/.omp/extensions
    $ompTargetDirs = @(
        (Join-Path $OmpDir "extensions"),
        (Join-Path "$env:USERPROFILE\.omp" "extensions")
    ) | Select-Object -Unique

    $srcExt = Join-Path $PSScriptRoot "extensions\no-hard-delete.ts"
    if (Test-Path $srcExt) {
        foreach ($extDir in $ompTargetDirs) {
            if (-not (Test-Path $extDir) -and -not $DryRun) {
                New-Item -ItemType Directory -Path $extDir -Force | Out-Null
            }
            $targetExt = Join-Path $extDir "no-hard-delete.ts"
            Write-Host "  -> Cai dat OMP extension sang $targetExt..." -ForegroundColor Green
            if (-not $DryRun) {
                Copy-Item -Path $srcExt -Destination $targetExt -Force
            }
        }
    }

    Write-Host "  -> Hoan tat kich hoat Trash Guard cho OMP." -ForegroundColor Green
}

function Get-EnvOrPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvName,
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [string]$Default,
        [switch]$AllowEmpty
    )
    $val = [Environment]::GetEnvironmentVariable($EnvName, "Process")
    if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    
    $hasDefault = $PSBoundParameters.ContainsKey('Default')
    while ($true) {
        $promptStr = $Prompt
        if ($hasDefault) { $promptStr = "$Prompt (Default: $Default)" }
        $inputVal = Read-Host $promptStr
        if (-not [string]::IsNullOrWhiteSpace($inputVal)) {
            return $inputVal.Trim()
        }
        if ($hasDefault) {
            return $Default
        }
        if ($AllowEmpty) {
            return ""
        }
        Write-Host "Error: '$EnvName' is required. Please provide a value." -ForegroundColor Red
    }
}

$aiBaseUrl = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "http://localhost:20128/v1"
$aiKey     = Get-EnvOrPrompt -EnvName "AI_API_KEY" -Prompt "AI API Key"
$jiraUrl   = Get-EnvOrPrompt -EnvName "JIRA_URL" -Prompt "Jira URL" -Default "https://jira.cybertech.vn"
$jiraToken = Get-EnvOrPrompt -EnvName "JIRA_PERSONAL_TOKEN" -Prompt "Jira Personal Token" -Default "YOUR_JIRA_PERSONAL_TOKEN"
$confUrl   = Get-EnvOrPrompt -EnvName "CONFLUENCE_URL" -Prompt "Confluence URL" -Default "https://conf.cybertech.vn"
$confToken = Get-EnvOrPrompt -EnvName "CONFLUENCE_PERSONAL_TOKEN" -Prompt "Confluence Personal Token" -Default "YOUR_CONFLUENCE_PERSONAL_TOKEN"
$ctxKey    = Get-EnvOrPrompt -EnvName "CONTEXT7_API_KEY" -Prompt "Context7 API Key" -AllowEmpty
$gitlabHost = Get-EnvOrPrompt -EnvName "GITLAB_HOST" -Prompt "GitLab Host" -Default "10.30.1.17"
$gitlabToken = Get-EnvOrPrompt -EnvName "GITLAB_TOKEN" -Prompt "GitLab Personal Token" -AllowEmpty

if (-not [string]::IsNullOrWhiteSpace($gitlabToken) -and -not $DryRun) {
    Write-Host "==> Configuring GitLab authentication for host '$gitlabHost'..." -ForegroundColor Cyan
    $proto = "https"
    if ($gitlabHost -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -or $gitlabHost -match ':80') { $proto = "http" }
    $glabCmd = "glab"
    if (Get-Command "glab" -ErrorAction SilentlyContinue) { $glabCmd = "glab" } elseif (Test-Path "$env:LOCALAPPDATA\Programs\glab\glab.exe") { $glabCmd = "$env:LOCALAPPDATA\Programs\glab\glab.exe" }
    try {
        & $glabCmd config set api_protocol $proto -g --host $gitlabHost 2>$null
        $tokenSec = $gitlabToken.Trim()
        & $glabCmd auth login --hostname $gitlabHost --token $tokenSec 2>$null
        Write-Host "  -> Logged in to GitLab ($gitlabHost) successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Could not configure glab auth automatically: $($_.Exception.Message)"
    }
}

$cbSourceDir = Join-Path $PSScriptRoot "mcp-servers\cloakbrowser"
$cbTargetDir = Get-CloakBrowserInstallDir
$cloakScriptPath = Setup-CloakBrowser -TargetDir $cbTargetDir -SourceDir $cbSourceDir -DryRun:$DryRun -SkipInstall:$SkipInstall
$escapedCloakScript = ($cloakScriptPath).Replace('\', '\\')

$templatesDir = Join-Path $PSScriptRoot "templates"

# 1. Config template
$configTemplateContent = $configTemplate
$customConfigTpl = Join-Path $templatesDir "config.yml"
if (Test-Path $customConfigTpl) {
    Write-Host "  -> Đọc template config.yml từ $customConfigTpl..." -ForegroundColor Cyan
    $configTemplateContent = Get-Content -Path $customConfigTpl -Raw -Encoding UTF8
}
$configContent = $configTemplateContent

# 2. Models template
$modelsTemplateContent = $modelsTemplate
$customModelsTpl = Join-Path $templatesDir "models.yml"
if (Test-Path $customModelsTpl) {
    Write-Host "  -> Đọc template models.yml từ $customModelsTpl..." -ForegroundColor Cyan
    $modelsTemplateContent = Get-Content -Path $customModelsTpl -Raw -Encoding UTF8
}
$modelsContent = $modelsTemplateContent.Replace("__AI_BASE_URL__", $aiBaseUrl).Replace("__AI_API_KEY__", $aiKey)

# 3. MCP template
$mcpTemplateContent = $mcpTemplate
$customMcpTpl = Join-Path $templatesDir "mcp.json"
if (Test-Path $customMcpTpl) {
    Write-Host "  -> Đọc template mcp.json từ $customMcpTpl..." -ForegroundColor Cyan
    $mcpTemplateContent = Get-Content -Path $customMcpTpl -Raw -Encoding UTF8
}
$mcpJson = $mcpTemplateContent.Replace("__JIRA_URL__", $jiraUrl).Replace("__JIRA_PERSONAL_TOKEN__", $jiraToken).Replace("__CONFLUENCE_URL__", $confUrl).Replace("__CONFLUENCE_PERSONAL_TOKEN__", $confToken).Replace("__CLOAKBROWSER_SCRIPT__", $escapedCloakScript)
if ($mcpJson.Contains("__GITNEXUS_PATH__")) {
    $mcpJson = $mcpJson.Replace("__GITNEXUS_PATH__", $absGn)
}
if ($mcpJson.Contains("__GITNEXUS_ARGS__")) {
    $mcpJson = $mcpJson.Replace("__GITNEXUS_ARGS__", $gitnexusArgsJson)
}
if ($mcpJson.Contains("__CONTEXT7_PATH__")) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_PATH__", $absCtx2)
}
if ($mcpJson.Contains("__CONTEXT7_CMD__")) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_CMD__", $context7Command)
}
if ($mcpJson.Contains("__CONTEXT7_ARGS__")) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_ARGS__", $context7ArgsJson)
}
if ($ctxKey) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_API_KEY__", $ctxKey)
} else {
    # Anonymous mode: drop the env block so no placeholder key is ever sent.
    $mcpJson = $mcpJson -replace ',\s*"env":\s*\{\s*"CONTEXT7_API_KEY":\s*"__CONTEXT7_API_KEY__"\s*\}', ''
}

try {
    $mcpObj = $mcpJson | ConvertFrom-Json
    if ($mcpObj -and $mcpObj.mcpServers) {
        if ($EnableMemorix) {
            if (-not $mcpObj.mcpServers.PSObject.Properties['memorix']) {
                $mcpObj.mcpServers | Add-Member -MemberType NoteProperty -Name "memorix" -Value ([PSCustomObject]@{
                    command = "memorix"
                    args    = @("serve", "--mode", "lite")
                })
            }
        } else {
            if ($mcpObj.mcpServers.PSObject.Properties['memorix']) {
                $mcpObj.mcpServers.PSObject.Properties.Remove('memorix')
            }
        }
        $mcpJson = $mcpObj | ConvertTo-Json -Depth 10
    }
} catch {
    Write-Warning "Không thể cập nhật cấu hình memorix trong mcp.json: $($_.Exception.Message)"
}

$files = [ordered]@{
    "mcp.json"   = $mcpJson
    "models.yml" = $modelsContent
    "config.yml" = $configContent
}

foreach ($entry in $files.GetEnumerator()) {
    $targetFileName = $entry.Key
    $templateContent = $entry.Value
    $targetPath = Join-Path $OmpDir $targetFileName

    if (Test-Path $targetPath) {
        $bakPath = "$targetPath.bak"
        if ($targetFileName -eq "mcp.json") {
            if ($isForce) {
                Write-Host "  -> File cấu hình '$targetFileName' đã tồn tại. [-Force / -OverwriteAll] Tự động sao lưu và ghi đè." -ForegroundColor Yellow
                if (-not $DryRun) {
                    Copy-Item -Path $targetPath -Destination $bakPath -Force
                    Write-Host "     Đã sao lưu sang $bakPath" -ForegroundColor DarkGray
                    Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                }
            } else {
                $choice = Read-Host "[?] File cấu hình 'mcp.json' đã tồn tại. Bạn có muốn [O]verwrite (ghi đè), [M]erge (hợp nhất server cũ và mới), hay [S]kip (bỏ qua)? [O/M/s]"
                $choice = if ($choice) { $choice.Trim() } else { "" }
                if ($choice -match '^[mM]$') {
                    Write-Host "  -> Đang hợp nhất $targetFileName (sao lưu sang $bakPath)..." -ForegroundColor Cyan
                    if (-not $DryRun) {
                        Copy-Item -Path $targetPath -Destination $bakPath -Force
                        Write-Host "     Đã sao lưu sang $bakPath" -ForegroundColor DarkGray
                        try {
                            $existingJson = Get-Content -Path $targetPath -Raw -Encoding UTF8 | ConvertFrom-Json
                            $newJson = $templateContent | ConvertFrom-Json
                            if (-not $existingJson.PSObject.Properties['mcpServers']) {
                                $existingJson | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
                            }
                            if ($newJson -and $newJson.mcpServers) {
                                foreach ($prop in $newJson.mcpServers.PSObject.Properties) {
                                    if (-not $existingJson.mcpServers.PSObject.Properties[$prop.Name]) {
                                        $existingJson.mcpServers | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value
                                    }
                                }
                            }
                            $mergedJsonStr = $existingJson | ConvertTo-Json -Depth 10
                            Set-Content -Path $targetPath -Value $mergedJsonStr -Encoding UTF8
                            Write-Host "  -> Đã hợp nhất $targetFileName thành công." -ForegroundColor Green
                        } catch {
                            Write-Warning "Không thể hợp nhất JSON: $($_.Exception.Message). Tiến hành ghi đè bằng template."
                            Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                        }
                    }
                } elseif ($choice -match '^[oO]$') {
                    Write-Host "  -> Ghi đè file $targetFileName (đã sao lưu sang $bakPath)" -ForegroundColor Green
                    if (-not $DryRun) {
                        Copy-Item -Path $targetPath -Destination $bakPath -Force
                        Write-Host "     Đã sao lưu sang $bakPath" -ForegroundColor DarkGray
                        Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                    }
                } else {
                    Write-Host "  -> Bỏ qua $targetFileName (giữ nguyên file hiện tại)." -ForegroundColor Yellow
                }
            }
        } else {
            # File YAML (config.yml, models.yml)
            if ($isForce) {
                Write-Host "  -> File cấu hình '$targetFileName' đã tồn tại. [-Force / -OverwriteAll] Tự động sao lưu và ghi đè." -ForegroundColor Yellow
                if (-not $DryRun) {
                    Copy-Item -Path $targetPath -Destination $bakPath -Force
                    Write-Host "     Đã sao lưu sang $bakPath" -ForegroundColor DarkGray
                    Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                }
            } else {
                $choice = Read-Host "[?] File cấu hình '$targetFileName' đã tồn tại. Bạn có muốn [O]verwrite (ghi đè) hay [S]kip (bỏ qua)? [O/s]"
                $choice = if ($choice) { $choice.Trim() } else { "" }
                if ($choice -match '^[oO]$') {
                    Write-Host "  -> Ghi đè file $targetFileName (đã sao lưu sang $bakPath)" -ForegroundColor Green
                    if (-not $DryRun) {
                        Copy-Item -Path $targetPath -Destination $bakPath -Force
                        Write-Host "     Đã sao lưu sang $bakPath" -ForegroundColor DarkGray
                        Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
                    }
                } else {
                    Write-Host "  -> Bỏ qua $targetFileName (giữ nguyên file hiện tại)." -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "  -> Creating $targetPath" -ForegroundColor Green
        if (-not $DryRun) {
            Set-Content -Path $targetPath -Value $templateContent -Encoding UTF8
        }
    }
}


Write-Host "==> Copying static files and skills..." -ForegroundColor Cyan
foreach ($mdFile in @("AGENTS.md", "RULES.md", "SYSTEM.md")) {
    $srcPath = Join-Path $PSScriptRoot $mdFile
    $targetPath = Join-Path $OmpDir $mdFile
    if (Test-Path $srcPath) {
        Write-Host "  -> Copying $mdFile to $targetPath (overwrite)" -ForegroundColor Green
        if (-not $DryRun) {
            Copy-Item -Path $srcPath -Destination $targetPath -Force
        }
    }
}
$targetAgentsPath = Join-Path $OmpDir "AGENTS.md"
if ($EnableMemorix) {
    $memSectionPath = Join-Path $templatesDir "memorix-agents-section.md"
    if (Test-Path $memSectionPath) {
        Write-Host "  -> Tích hợp hướng dẫn Memorix vào $targetAgentsPath..." -ForegroundColor Green
        if (-not $DryRun -and (Test-Path $targetAgentsPath)) {
            $memSectionContent = Get-Content -Path $memSectionPath -Raw -Encoding UTF8
            Add-Content -Path $targetAgentsPath -Value "`r`n$memSectionContent" -Encoding UTF8
        }
    }
}

$srcSkills = Join-Path $PSScriptRoot "skills"
$targetSkills = Join-Path $OmpDir "skills"
if (Test-Path $srcSkills) {
    if (-not (Test-Path $targetSkills)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $targetSkills | Out-Null
        }
    }

    if ($EnableMemorix) {
        Write-Host "  -> Copying toàn bộ skills/ (bao gồm memorix) sang $targetSkills (overwrite)" -ForegroundColor Green
        if (-not $DryRun) {
            Get-ChildItem -Path $srcSkills -Directory | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $targetSkills -Recurse -Force
            }
        }
    } else {
        Write-Host "  -> Copying skills/ (bỏ qua memorix-*) sang $targetSkills (overwrite)" -ForegroundColor Green
        if (-not $DryRun) {
            Get-ChildItem -Path $srcSkills -Directory | Where-Object { $_.Name -notlike "memorix-*" } | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $targetSkills -Recurse -Force
            }
        }

        # Dọn dẹp các kỹ năng memorix-* đã tồn tại trong $targetSkills bằng cách chuyển vào Thùng rác (Recycle Bin)
        if (Test-Path $targetSkills) {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
            $existingMemorixSkills = Get-ChildItem -Path $targetSkills -Directory -Filter "memorix-*" -ErrorAction SilentlyContinue
            foreach ($memSkill in $existingMemorixSkills) {
                Write-Host "  -> Di chuyển kỹ năng '$($memSkill.Name)' vào Thùng rác (Recycle Bin)..." -ForegroundColor Yellow
                if (-not $DryRun) {
                    try {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                            $memSkill.FullName,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                    } catch {
                        Write-Warning "Không thể di chuyển '$($memSkill.FullName)' vào Thùng rác: $($_.Exception.Message)"
                    }
                }
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Trash Guard Protection (Hard-delete prevention for OMP via extension)
# ------------------------------------------------------------------------------
Setup-TrashGuard -OmpDir $OmpDir -DryRun:$DryRun -SkipInstall:$SkipInstall

Write-Host "`nBootstrap finished. Set required environment variables if using Jira or Router:" -ForegroundColor Green
Write-Host '  $env:AI_API_KEY = "..."'
Write-Host '  $env:JIRA_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONFLUENCE_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONTEXT7_API_KEY = "..." (optional, higher rate limits)'
Write-Host '  gitnexus index empty? run: gitnexus analyze'