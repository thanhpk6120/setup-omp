# bootstrap.ps1 - Bootstrap .omp environment on fresh machine
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [string]$OmpDir = "$env:USERPROFILE\.omp\agent"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Checking runtime dependencies..." -ForegroundColor Cyan
foreach ($tool in @("node", "npm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing '$tool' in PATH. Please install it first."
    }
}

# MCP tools (context7, gitnexus, memorix) require Node >= 18.
$nodeVerRaw = (node -v 2>$null | Out-String).Trim()
try {
    $nodeVer = [version]($nodeVerRaw.TrimStart('v'))
} catch {
    throw "Không thể xác định version của Node.js: '$nodeVerRaw'"
}
if ($nodeVer -lt [version]"22.18.0") {
    throw "Yêu cầu Node.js >= 22.18.0 (do memorix yêu cầu >= 22.18.0, gitnexus yêu cầu ^22.18.0 || >= 24.11.0, context7 yêu cầu >= 20.18.1). Phiên bản hiện tại: '$nodeVerRaw'. Vui lòng nâng cấp Node.js."
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


if (-not $SkipInstall -and -not (Get-Command "memorix" -ErrorAction SilentlyContinue)) {
    Write-Host "==> Installing memorix globally..." -ForegroundColor Cyan
    if (-not $DryRun) {
        npm install -g memorix --silent
    }
}

# Memorix OMP hooks live in the memorix-omp-package plugin (extensions/memorix.js),
# registered by `memorix setup --agent omp --global` — `npm install -g` alone is not enough.
if (-not $SkipInstall) {
    Write-Host "==> Registering memorix OMP plugin + hooks..." -ForegroundColor Cyan
    if (-not $DryRun) {
        try {
            memorix setup --agent omp --global
        } catch {
            Write-Warning "memorix setup failed (hooks not registered, run it manually): $($_.Exception.Message)"
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
#   memorix:           https://github.com/AVIDS2/memorix (setup --agent omp --global registers OMP hooks)
#   gitnexus:          https://github.com/abhigyanpatwari/GitNexus (global install + absolute path avoids npx cold-start timeout)
#   mcp-atlassian:     https://mcp-atlassian.soomiles.com/docs/installation (pinned via uvx --from)
#   context7:          https://github.com/upstash/context7 (optional CONTEXT7_API_KEY for higher rate limits)
$mcpTemplate = @'
{
  "mcpServers": {
    "memorix": {
      "command": "memorix",
      "args": ["serve", "--mode", "lite"]
    },
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
    $defaultLetter = if ($defaultDrive.DeviceID) { $defaultDrive.DeviceID } else { "$($defaultDrive.Name):" }

    if ([Environment]::GetEnvironmentVariable("CI") -or -not [Environment]::UserInteractive) {
        return "$defaultLetter\mcp-servers\cloakbrowser"
    }

    Write-Host "`n==> Quet danh sach o dia (Local Drives) de cai dat CloakBrowser MCP:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $devId = if ($d.DeviceID) { $d.DeviceID } else { "$($d.Name):" }
        $volName = if ($d.VolumeName) { " ($($d.VolumeName))" } else { "" }
        $freeGB = [math]::Round(((if ($d.FreeSpace) { $d.FreeSpace } else { $d.Free }) / 1GB), 2)
        $sizeGB = if ($d.Size) { [math]::Round(($d.Size / 1GB), 2) } else { "N/A" }
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
                $chosenLetter = if ($chosen.DeviceID) { $chosen.DeviceID } else { "$($chosen.Name):" }
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

    Write-Host "==> Cai dat Trash Guard (bao ve chan xoa cung)..." -ForegroundColor Cyan

    # 1. Cai dat OMP Extension (no-hard-delete.ts) vao OmpDir va ~/.omp/extensions
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

    # Cac buoc cai dat global duoi day chi chay khi khong co co -SkipInstall
    if ($SkipInstall) {
        Write-Host "  -> Bo qua cac buoc cau hinh he thong toan cuc (-SkipInstall duoc bat)." -ForegroundColor Yellow
        return
    }

    $targetDir = "$env:USERPROFILE\.trash-guard"
    if (-not (Test-Path $targetDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }

    # 2. Copy trash-guard scripts tu repo sang $targetDir
    $srcTrashGuard = Join-Path $PSScriptRoot "trash-guard"
    if (Test-Path $srcTrashGuard) {
        Write-Host "  -> Copy cac script trash-guard sang $targetDir..." -ForegroundColor Green
        if (-not $DryRun) {
            Copy-Item -Path "$srcTrashGuard\*" -Destination $targetDir -Force -Recurse
        }
    }

    # 3. Cau hinh Claude Code PreToolUse Hook trong settings.json
    $claudeDir = "$env:USERPROFILE\.claude"
    $claudeSettingsPath = Join-Path $claudeDir "settings.json"
    Write-Host "  -> Cau hinh Claude Code PreToolUse hook trong $claudeSettingsPath..." -ForegroundColor Green
    if (-not $DryRun) {
        try {
            if (-not (Test-Path $claudeDir)) {
                New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
            }
            if (-not (Test-Path $claudeSettingsPath)) {
                [System.IO.File]::WriteAllText($claudeSettingsPath, "{}", [System.Text.Encoding]::UTF8)
            }
            $rawJson = Get-Content -LiteralPath $claudeSettingsPath -Raw -Encoding UTF8
            $settings = $rawJson | ConvertFrom-Json
            if (-not $settings.hooks) {
                $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
            }
            if (-not $settings.hooks.PreToolUse) {
                $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @()
            }

            $cmdPath = "$env:USERPROFILE\.trash-guard\claude-pre-tool.cmd" -replace '\\', '/'
            $existing = @($settings.hooks.PreToolUse)
            $hasBashHook = $false
            $hasPwshHook = $false
            foreach ($entry in $existing) {
                if ($entry.matcher -eq "Bash" -and ($entry.hooks | Where-Object { $_.command -like "*claude-pre-tool*" })) {
                    $hasBashHook = $true
                }
                if ($entry.matcher -eq "PowerShell" -and ($entry.hooks | Where-Object { $_.command -like "*claude-pre-tool*" })) {
                    $hasPwshHook = $true
                }
            }

            $updated = [System.Collections.ArrayList]::new($existing)
            if (-not $hasBashHook) {
                $bashHookObj = [PSCustomObject]@{
                    matcher = "Bash"
                    hooks = @(
                        [PSCustomObject]@{
                            type = "command"
                            command = $cmdPath
                            timeout = 15
                        }
                    )
                }
                [void]$updated.Add($bashHookObj)
            }
            if (-not $hasPwshHook) {
                $pwshHookObj = [PSCustomObject]@{
                    matcher = "PowerShell"
                    hooks = @(
                        [PSCustomObject]@{
                            type = "command"
                            command = $cmdPath
                            timeout = 15
                        }
                    )
                }
                [void]$updated.Add($pwshHookObj)
            }

            $settings.hooks.PreToolUse = @($updated)
            $newJson = $settings | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($claudeSettingsPath, $newJson, [System.Text.Encoding]::UTF8)
            Write-Host "    Claude Code PreToolUse hook da duoc kich hoat." -ForegroundColor Gray
        } catch {
            Write-Warning "Khong the cap nhat Claude Code settings.json: $($_.Exception.Message)"
        }
    }

    # 4. Cau hinh PowerShell Profile hook
    Write-Host "  -> Cau hinh PowerShell Profile hook..." -ForegroundColor Green
    if (-not $DryRun) {
        $ps1ScriptPath = "$env:USERPROFILE\.trash-guard\trash-guard.ps1"
        $profileIncludeLine = "if (Test-Path '$ps1ScriptPath') { . '$ps1ScriptPath' }"
        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        $profilesToCheck = @(
            "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
            "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
            (Join-Path $myDocs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
            (Join-Path $myDocs "PowerShell\Microsoft.PowerShell_profile.ps1")
        ) | Select-Object -Unique

        foreach ($prof in $profilesToCheck) {
            $profDir = Split-Path -Parent $prof
            if (-not (Test-Path $profDir)) {
                New-Item -ItemType Directory -Path $profDir -Force | Out-Null
            }
            $existingContent = if (Test-Path $prof) { Get-Content -LiteralPath $prof -Raw -Encoding UTF8 } else { "" }
            if ($existingContent -notlike "*trash-guard.ps1*") {
                Add-Content -LiteralPath $prof -Value "`n# Trash Guard Protection`n$profileIncludeLine`n" -Encoding UTF8
                Write-Host "    Da them trash-guard hook vao $prof" -ForegroundColor Gray
            }
        }
    }

    # 5. Cau hinh Git Bash & BASH_ENV hook
    Write-Host "  -> Cau hinh Git Bash va BASH_ENV hook..." -ForegroundColor Green
    if (-not $DryRun) {
        $shScriptPath = "$env:USERPROFILE\.trash-guard\trash-guard.sh"
        $bashIncludeLine = '[ -f "$HOME/.trash-guard/trash-guard.sh" ] && . "$HOME/.trash-guard/trash-guard.sh"'

        foreach ($bashFile in @("$env:USERPROFILE\.bashrc", "$env:USERPROFILE\.bash_profile")) {
            $existingBash = if (Test-Path $bashFile) { Get-Content -LiteralPath $bashFile -Raw -Encoding UTF8 } else { "" }
            if ($existingBash -notlike "*trash-guard.sh*") {
                Add-Content -LiteralPath $bashFile -Value "`n# Trash Guard Protection`n$bashIncludeLine`n" -Encoding UTF8
                Write-Host "    Da them trash-guard hook vao $bashFile" -ForegroundColor Gray
            }
        }

        # Set User environment variable BASH_ENV
        try {
            $shPathUnix = $shScriptPath -replace '\\', '/'
            $currentBashEnv = [Environment]::GetEnvironmentVariable("BASH_ENV", "User")
            if ($currentBashEnv -ne $shPathUnix) {
                [Environment]::SetEnvironmentVariable("BASH_ENV", $shPathUnix, "User")
                $env:BASH_ENV = $shPathUnix
                Write-Host "    Da thiet lap User environment variable BASH_ENV = $shPathUnix" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Khong the thiet lap bien moi truong BASH_ENV: $($_.Exception.Message)"
        }
    }

    # 6. Cau hinh DSH (DeepSeek Harness)
    Write-Host "  -> Cau hinh DSH (DeepSeek Harness)..." -ForegroundColor Green
    if (-not $DryRun) {
        $dshDir = "$env:USERPROFILE\.dsh"
        if (-not (Test-Path $dshDir)) {
            New-Item -ItemType Directory -Path $dshDir -Force | Out-Null
        }
        $agentsMdPath = Join-Path $dshDir "AGENTS.md"
        $dshRuleB64 = "CiMgUVVZIFThuq5DIFRJw4pOIFFVWeG6vlQgKE1BTkRBVE9SWSkKVFVZ4buGVCDEkOG7kEkgS0jDlE5HIMSQxq/hu6JDIHhvw6EgY+G7qW5nL3hvw6EgdsSpbmggdmnhu4VuIGZpbGUgaG/hurdjIHRoxrAgbeG7pWMgKGPhuqVtIGTDuW5nIHJtLCBSZW1vdmUtSXRlbSwgZGVsLCBybWRpciwgc2hyZWQuLi4pLgpC4bquVCBCVeG7mEMgZMO5bmcgbOG7h25oICd0cmFzaCA8xJHGsOG7nW5nX2ThuqtuPicgxJHhu4MgZGkgY2h1eeG7g24gdsOgbyB0aMO5bmcgcsOhYy4K"
        $dshRule = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($dshRuleB64))
        $existingAgentsMd = if (Test-Path $agentsMdPath) { Get-Content -LiteralPath $agentsMdPath -Raw -Encoding UTF8 } else { "" }
        if ($existingAgentsMd -notlike "*trash <*") {
            Add-Content -LiteralPath $agentsMdPath -Value $dshRule -Encoding UTF8
            Write-Host "    Da cap nhat quy tac chan xoa cung vao $agentsMdPath" -ForegroundColor Gray
        }
    }

    Write-Host "  -> Hoan tat kich hoat Trash Guard cho OMP, DSH, Claude Code va Shell." -ForegroundColor Green
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
        $promptStr = if ($hasDefault) { "$Prompt (Default: $Default)" } else { $Prompt }
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

$aiBaseUrl = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "https://openrouter.ai/api/v1"
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
    $proto = if ($gitlabHost -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' -or $gitlabHost -match ':80') { "http" } else { "https" }
    $glabCmd = if (Get-Command "glab" -ErrorAction SilentlyContinue) { "glab" } elseif (Test-Path "$env:LOCALAPPDATA\Programs\glab\glab.exe") { "$env:LOCALAPPDATA\Programs\glab\glab.exe" } else { "glab" }
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

$mcpJson = $mcpTemplate.Replace("__JIRA_URL__", $jiraUrl).Replace("__JIRA_PERSONAL_TOKEN__", $jiraToken).Replace("__CONFLUENCE_URL__", $confUrl).Replace("__CONFLUENCE_PERSONAL_TOKEN__", $confToken).Replace("__GITNEXUS_ARGS__", $gitnexusArgsJson).Replace("__CONTEXT7_CMD__", $context7Command).Replace("__CONTEXT7_ARGS__", $context7ArgsJson).Replace("__CLOAKBROWSER_SCRIPT__", $escapedCloakScript)
if ($ctxKey) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_API_KEY__", $ctxKey)
} else {
    # Anonymous mode: drop the env block so no placeholder key is ever sent.
    $mcpJson = $mcpJson -replace ',\s*"env":\s*\{\s*"CONTEXT7_API_KEY":\s*"__CONTEXT7_API_KEY__"\s*\}', ''
}
$files = @{
    "mcp.json"   = $mcpJson
    "models.yml" = $modelsTemplate.Replace("__AI_BASE_URL__", $aiBaseUrl).Replace("__AI_API_KEY__", $aiKey)
    "config.yml" = $configTemplate
}
foreach ($entry in $files.GetEnumerator()) {
    $targetPath = Join-Path $OmpDir $entry.Key
    if (Test-Path $targetPath) {
        Write-Host "  -> Skipping $targetPath (already exists)" -ForegroundColor Yellow
    } else {
        Write-Host "  -> Creating $targetPath" -ForegroundColor Green
        if (-not $DryRun) {
            Set-Content -Path $targetPath -Value $entry.Value -Encoding UTF8
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
$srcSkills = Join-Path $PSScriptRoot "skills"
$targetSkills = Join-Path $OmpDir "skills"
if (Test-Path $srcSkills) {
    Write-Host "  -> Copying skills/ to $targetSkills (overwrite)" -ForegroundColor Green
    if (-not $DryRun) {
        Copy-Item -Path $srcSkills -Destination $targetSkills -Recurse -Force
    }
}

# ------------------------------------------------------------------------------
# Trash Guard Protection (Hard-delete prevention for OMP, Claude Code & Shell)
# ------------------------------------------------------------------------------
Setup-TrashGuard -OmpDir $OmpDir -DryRun:$DryRun -SkipInstall:$SkipInstall

Write-Host "`nBootstrap finished. Set required environment variables if using Jira or Router:" -ForegroundColor Green
Write-Host '  $env:AI_API_KEY = "..."'
Write-Host '  $env:JIRA_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONFLUENCE_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONTEXT7_API_KEY = "..." (optional, higher rate limits)'
Write-Host '  gitnexus index empty? run: gitnexus analyze'