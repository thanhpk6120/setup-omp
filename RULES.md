# Global Rules

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the rules in this document without exception. NEVER truncate, omit, skip, or summarize away any rule. Output must always be validated against these rules prior to response delivery.

## 0. PRECEDENCE, DELEGATION, SKILLS & PLUGINS/MCP [MANDATORY PRE-FLIGHT — NEVER SKIP]
- **PRECEDENCE RULE:** Delegation, Skill, and Plugin/MCP Orchestration rules ALWAYS OVERRIDE "Think Before Coding", "Simplicity", and "Goal-Driven". Whenever a task involves ≥2 steps, multi-file scope, or investigation, delegation is MANDATORY. "Simplicity" and "Goal-Driven" apply *within* the subagent's scope, NOT as an excuse for the Main Agent to do everything directly.
- **OUTPUT PREFIX (MANDATORY BEFORE ANY TOOL CALL):** 
  The Main Agent MUST output a reasoning line before calling ANY tool:
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill name(s) or None> | Plugins/MCP: <Plugin/MCP tool(s) or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`
- **Mandatory Skills Resolution:** Scan and apply matching skills from `skills/*/SKILL.md` (e.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`, `sql-*`, `java-*`, `poka-yoke`...). Never invent ad-hoc procedures when an established skill exists.
- **Mandatory Plugins / MCP Tools Resolution:** Route domain-specific requests to specialized MCP tools instead of manual CLI/bash/grep:
  - Code knowledge graph, call graphs, impact analysis, blast radius, symbol traces: MUST use **GitNexus** (`mcp__gitnexus_*`).
  - Project memory, context briefs, decisions, historical bugfixes: MUST use **Memorix** (`mcp__memorix_*`).
  - Headless browser automation, scraping, web interaction: MUST use **CloakBrowser** (`mcp__cloakbrowser_*`).
  - Jira tickets, issues, sprints, worklogs: MUST use **Jira** (`mcp__company_atlassian_jira_*`).
  - Confluence docs, specs, knowledge base: MUST use **Confluence** (`mcp__company_atlassian_confluence_*`).
  - External library documentation & code examples: MUST use **Context7** (`mcp__context7_*`).
- **Delegation logic:**
  - Prefer delegating to specialized subagents (`scout`, `task`, `reviewer`, `docs-*`, `dely-*`) in parallel batches via the `task` tool whenever work has 2+ steps, multi-file scope, or distinct inspection/implementation slices.
  - Do not sequentially inspect > 1 file or serialize independent tasks in the main agent. Fan out concurrently to minimize latency, ensure accuracy, and save main context window.
  - Main agent acts primarily as Dispatcher & Integrator.

## 1. Global Rules
- Always respond in Vietnamese (except code identifiers, error strings, shell commands, URLs).
- Never commit, branch, or open PRs unless explicitly requested.
- Never delete user files. Clean only temporary files created by the current task.
- Create/update files only in the current workspace; ask before editing outside it.
- Do not stop or downgrade scope/model/agents solely for cost warnings. Continue when technically possible; report platform blocks.
- Disclose failed commands/tests and incomplete verification. Never claim unverified success.
- Do not refactor, reformat, or improve unrelated code. Match project style.
- Every changed line must trace directly to the user's request.
- MANDATORY RULE COMPLIANCE: AI MUST strictly follow ALL rules in AGENTS.md and RULES.md without exception. NEVER skip, omit, or downgrade any rule. ALWAYS verify final output against every applicable rule for compliance before responding.
