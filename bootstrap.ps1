# bootstrap.ps1 - Bootstrap .omp environment on fresh machine
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipInstall,
    [string]$OmpDir = "$env:USERPROFILE\.omp\agent",
    [string]$CloakBrowserPath = "D:\Thanhpk\AI\cloakbrowser\mcp-server-full.mjs"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Checking runtime dependencies..." -ForegroundColor Cyan
foreach ($tool in @("node", "npm", "git")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Missing '$tool' in PATH. Please install it first."
    }
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
# cold-cache stalls exceeding the 30s MCP timeout
# (https://github.com/abhigyanpatwari/GitNexus README, "Fastest MCP startup").
$gitnexusArgsJson = '"/c", "npx", "-y", "gitnexus@latest", "mcp"'
if (-not $SkipInstall) {
    Write-Host "==> Installing gitnexus globally..." -ForegroundColor Cyan
    if (-not $DryRun) {
        try {
            npm install -g gitnexus --silent
            $gitnexusBin = Get-Command "gitnexus" -ErrorAction SilentlyContinue
            if ($gitnexusBin -and $gitnexusBin.Source) {
                $absGitnexus = $gitnexusBin.Source -replace '\\', '\\'
                $gitnexusArgsJson = '"/c", "' + $absGitnexus + '", "mcp"'
            }
        } catch {
            Write-Warning "gitnexus global install failed, falling back to npx: $($_.Exception.Message)"
        }
    }
}

$context7Command = '"cmd"'
$context7ArgsJson = '"/c", "npx", "-y", "@upstash/context7-mcp"'
if (-not $SkipInstall) {
    Write-Host "==> Installing context7 globally..." -ForegroundColor Cyan
    if (-not $DryRun) {
        try {
            npm install -g @upstash/context7-mcp --silent
            $npmGlobalRoot = npm root -g
            $ctxJsPath = Join-Path $npmGlobalRoot "@upstash\context7-mcp\dist\index.js"
            if (Test-Path $ctxJsPath) {
                $absCtxJs = $ctxJsPath -replace '\\', '\\'
                $context7Command = '"node"'
                $context7ArgsJson = '"' + $absCtxJs + '"'
            }
        } catch {
            Write-Warning "context7 global install failed, falling back to npx: $($_.Exception.Message)"
        }
    }
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
#   cloakbrowser:      local project server
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
    },
    "cloakbrowser": {
      "command": "node",
      "args": ["__CLOAKBROWSER_PATH__"]
    }
  }
}
'@

$modelsTemplate = @'
providers:
  9router:
    baseUrl: __ROUTER_BASE_URL__
    api: openai-completions
    apiKey: __ROUTER_API_KEY__
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
function Get-ConfigValue {
    param([string]$EnvName, [string]$Prompt, [string]$Default)
    $val = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    $inputVal = Read-Host "$Prompt (Default: $Default)"
    if ([string]::IsNullOrWhiteSpace($inputVal)) { return $Default }
    return $inputVal.Trim()
}

$routerUrl = Get-ConfigValue "ROUTER_BASE_URL" "Provider Base URL" "https://9router.thanhpk.io.vn/v1"
$routerKey = Get-ConfigValue "ROUTER_API_KEY" "Provider API Key" "YOUR_ROUTER_API_KEY"
$jiraUrl   = Get-ConfigValue "JIRA_URL" "Jira URL" "https://jira.cybertech.vn"
$jiraToken = Get-ConfigValue "JIRA_PERSONAL_TOKEN" "Jira Personal Token" "YOUR_JIRA_PERSONAL_TOKEN"
$confUrl   = Get-ConfigValue "CONFLUENCE_URL" "Confluence URL" "https://conf.cybertech.vn"
$confToken = Get-ConfigValue "CONFLUENCE_PERSONAL_TOKEN" "Confluence Personal Token" "YOUR_CONFLUENCE_PERSONAL_TOKEN"
$ctxKey    = Get-ConfigValue "CONTEXT7_API_KEY" "Context7 API Key" ""
$escapedCloakBrowser = $CloakBrowserPath -replace '\\', '\\'

$mcpJson = $mcpTemplate.Replace("__JIRA_URL__", $jiraUrl).Replace("__JIRA_PERSONAL_TOKEN__", $jiraToken).Replace("__CONFLUENCE_URL__", $confUrl).Replace("__CONFLUENCE_PERSONAL_TOKEN__", $confToken).Replace("__CLOAKBROWSER_PATH__", $escapedCloakBrowser).Replace("__GITNEXUS_ARGS__", $gitnexusArgsJson).Replace("__CONTEXT7_CMD__", $context7Command).Replace("__CONTEXT7_ARGS__", $context7ArgsJson)
if ($ctxKey) {
    $mcpJson = $mcpJson.Replace("__CONTEXT7_API_KEY__", $ctxKey)
} else {
    # Anonymous mode: drop the env block so no placeholder key is ever sent.
    $mcpJson = $mcpJson -replace ',\s*"env":\s*\{\s*"CONTEXT7_API_KEY":\s*"__CONTEXT7_API_KEY__"\s*\}', ''
}
if (-not (Test-Path $CloakBrowserPath)) {
    Write-Warning "CloakBrowser server not found at '$CloakBrowserPath' - omitting cloakbrowser from mcp.json"
    $mcpJson = $mcpJson -replace ',\s*"cloakbrowser":\s*\{\s*"command":\s*"node",\s*"args":\s*\["[^\]]*"\]\s*\}', ''
}

$files = @{
    "mcp.json"   = $mcpJson
    "models.yml" = $modelsTemplate.Replace("__ROUTER_BASE_URL__", $routerUrl).Replace("__ROUTER_API_KEY__", $routerKey)
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
Write-Host '  $env:ROUTER_API_KEY = "..."'
Write-Host '  $env:JIRA_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONFLUENCE_PERSONAL_TOKEN = "..."'
Write-Host '  $env:CONTEXT7_API_KEY = "..." (optional, higher rate limits)'
Write-Host '  gitnexus index empty? run: gitnexus analyze'