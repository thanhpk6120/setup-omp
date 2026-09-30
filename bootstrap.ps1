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
      "command": "uvx",
      "args": ["--from", "mcp-atlassian==0.23.1", "mcp-atlassian"],
      "env": {
        "JIRA_URL": "__JIRA_URL__",
        "JIRA_PERSONAL_TOKEN": "__JIRA_PERSONAL_TOKEN__",
        "CONFLUENCE_URL": "__CONFLUENCE_URL__",
        "CONFLUENCE_PERSONAL_TOKEN": "__CONFLUENCE_PERSONAL_TOKEN__",
        "TOOLSETS": "jira,confluence"
      }
    },
    "context7": {
      "command": __CONTEXT7_CMD__,
      "args": [__CONTEXT7_ARGS__],
      "env": {
        "CONTEXT7_API_KEY": "__CONTEXT7_API_KEY__"
      }
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

$aiBaseUrl = Get-EnvOrPrompt -EnvName "AI_BASE_URL" -Prompt "AI Base URL" -Default "https://9router.thanhpk.io.vn/v1"
$aiKey     = Get-EnvOrPrompt -EnvName "AI_API_KEY" -Prompt "AI API Key"
$jiraUrl   = Get-EnvOrPrompt -EnvName "JIRA_URL" -Prompt "Jira URL" -Default "https://jira.cybertech.vn"
$jiraToken = Get-EnvOrPrompt -EnvName "JIRA_PERSONAL_TOKEN" -Prompt "Jira Personal Token" -Default "YOUR_JIRA_PERSONAL_TOKEN"
$confUrl   = Get-EnvOrPrompt -EnvName "CONFLUENCE_URL" -Prompt "Confluence URL" -Default "https://conf.cybertech.vn"
$confToken = Get-EnvOrPrompt -EnvName "CONFLUENCE_PERSONAL_TOKEN" -Prompt "Confluence Personal Token" -Default "YOUR_CONFLUENCE_PERSONAL_TOKEN"
$ctxKey    = Get-EnvOrPrompt -EnvName "CONTEXT7_API_KEY" -Prompt "Context7 API Key" -AllowEmpty

$mcpJson = $mcpTemplate.Replace("__JIRA_URL__", $jiraUrl).Replace("__JIRA_PERSONAL_TOKEN__", $jiraToken).Replace("__CONFLUENCE_URL__", $confUrl).Replace("__CONFLUENCE_PERSONAL_TOKEN__", $confToken).Replace("__GITNEXUS_ARGS__", $gitnexusArgsJson).Replace("__CONTEXT7_CMD__", $context7Command).Replace("__CONTEXT7_ARGS__", $context7ArgsJson)
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
        if (Test-Path $targetPath) {
            Write-Host "  -> Skipping $targetPath (already exists)" -ForegroundColor Yellow
        } else {
            Write-Host "  -> Copying $mdFile to $targetPath" -ForegroundColor Green
            if (-not $DryRun) {
                Copy-Item -Path $srcPath -Destination $targetPath
            }
        }
    }
}

$srcSkills = Join-Path $PSScriptRoot "skills"
$targetSkills = Join-Path $OmpDir "skills"
if (Test-Path $srcSkills) {
    if (Test-Path $targetSkills) {
        Write-Host "  -> Skipping $targetSkills (already exists)" -ForegroundColor Yellow
    } else {
        Write-Host "  -> Copying skills/ to $targetSkills" -ForegroundColor Green
        if (-not $DryRun) {
            Copy-Item -Path $srcSkills -Destination $targetSkills -Recurse
        }
    }
}

Write-Host "`nBootstrap finished. Set required environment variables if using Jira or Router:" -ForegroundColor Green
Write-Host '  $env:AI_API_KEY = "..."'
Write-Host '  $env:JIRA_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONFLUENCE_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONTEXT7_API_KEY = "..." (optional, higher rate limits)'
Write-Host '  gitnexus index empty? run: gitnexus analyze'