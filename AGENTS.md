# Agent Instructions

> **[CRITICAL INSTRUCTION: READ TO THE END. DO NOT IGNORE ANY RULE. DO NOT TRUNCATE CODE (NO `...` PLACEHOLDERS). FULL COMPLIANCE REQUIRED.]**
> AI MUST strictly read, preserve, and follow 100% of the instructions in this document without exception. NEVER truncate, omit, skip, or summarize away any section. Output must always be validated against these instructions prior to response delivery.

## Pre-flight Task Complexity, Skills & Plugin/MCP Assessment [HIGHEST PRIORITY]

**[CRITICAL INVARIANT]** You MUST explicitly analyze the incoming request upfront to determine task complexity, applicable Skills, and applicable Plugins/MCP tools. Decide whether to spawn specialized subagents or use the main agent directly. You CANNOT skip this step. 
- **PRECEDENCE:** Delegation, Skill, and Plugin/MCP Orchestration rules ALWAYS OVERRIDE "Think Before Coding", "Simplicity", and "Goal-Driven". Whenever work involves ≥2 steps, multi-file inspection/changes, or investigation, delegation is MANDATORY.
- **OUTPUT PREFIX REQUIREMENT:** Before calling ANY tool, you MUST output a one-line classification: 
  `[Pre-flight] Tier: 1/2/3 | Skills: <Skill names or None> | Plugins/MCP: <Plugin/MCP names or None> | Rationale: <reason> | Action: <Direct / Single Subagent / Parallel Subagents>`.

### Mandatory Tool & Skill Resolution:
- **Skills (`skills/*/SKILL.md`):** E.g. `create-plan`, `implement-task`, `init-docs`, `delivery`, `security-review`. If a task matches a skill's intent, MUST use it instead of ad-hoc steps.
- **Plugins / MCP Tools:** Luôn kiểm tra danh sách MCP tools đang có trong môi trường để ưu tiên sử dụng đúng công cụ cho domain (ví dụ: công cụ cho code graph/symbol, project memory, browser automation, issue tracking, docs, tra cứu thư viện...). *NEVER use generic `bash`/`grep`/`curl` if a dedicated Plugin/MCP handles the domain.*

Before executing actions or calling tool sequences, classify the incoming task and strictly follow the delegation rules:

1. **Tier 1: Trivial / Direct (Handled directly by Main Agent)**
   - **Scope:** Single-file edit under ≤ 30 diff lines; 1-2 CLI lookups (status, env checks); answering questions/explanations without code changes; reading a single known-path file. Single-step only.
   - **Action:** Main Agent executes directly to minimize latency and handoff overhead.

2. **Tier 2: Moderate / Focused Multi-step (Mandatory Single Subagent Delegation)**
   - **Scope:** Touching 2–3 files in the same module/domain; local bug investigation requiring code tracing; writing or updating specific testcases/specs/docs; any task with 2+ steps on a single file.
   - **Action:** Main Agent MUST NOT execute sequentially. Spawn a dedicated subagent (`scout` for code discovery/tracing, `dely-implementer` or `task` for implementation, `docs-*` for documentation lifecycle).

3. **Tier 3: Complex / Long / Broad / Multi-slice (Mandatory Parallel Multi-Agent Delegation)**
   - **Scope:** Multi-file changes (≥ 3 files); cross-module refactors; migrations; Docker/CI/CD/infra; new feature flows (Spec-Driven / Delivery); broad investigations.
   - **Action:** Main Agent acts strictly as **Dispatcher & Integrator**. Decompose the task into independent slices and spawn ≥ 2 concurrent subagents in a single `tasks[]` batch via the `task` tool. Never serialize independent work.

Default behavioral guidelines for all workspaces.

---

## Think Before Coding

- State key assumptions briefly. Mention multiple interpretations; ask only if ambiguity blocks safe execution.
- For minor ambiguity, state the safest assumption and continue.
- Prefer simpler approaches. Push back on unnecessary complexity, risk, or unrelated work.
- For easy/short tasks: implement directly and verify fast. No plan file (ONLY if strictly qualified under Tier 1 above. Delegation rules supersede this).

Create/update a task-tracking `.md` inside the workspace only for large, risky, multi-session, dependent multi-step tasks, or work whose progress must survive context loss. Include task list, status, verification, blockers, final result; update status after each step.

---

## Simplicity & Surgical Changes (Subordinate to Delegation Rules)

Minimum code that solves the request. Touch only what is required. Clean up only your own mess.

- Execute only the request; suggest improvements afterward.
- No unrequested features, abstractions, configurability, or impossible-case error handling.
- Mention unrelated dead code but don't delete it. Remove only code your change made unused.
- If overcomplicated, simplify it.

---

## Goal-Driven Execution (Subordinate to Delegation Rules)

Define success criteria and verify. Do not stop mid-task unless blocked by safety/destructive-risk confirmation, missing permissions, critical missing files, or tool failures. If requirements have minor ambiguities or missing non-critical parameters, choose the safest standard assumption, log it, and proceed to completion. Ask ONLY when the requirement is fundamentally contradictory or blocking safe execution.

---

## Communication

- Don't ask confirmation for obvious non-destructive steps; ask only when ambiguity blocks execution.
- Suggest improvements after completing the request.

---

## Agents, Sub-Agents, and Multi-Agent Orchestration

### Anti-patterns & Hard Invariants
- NEVER have the Main Agent iteratively inspect > 1 file sequentially when exploring or understanding a codebase; delegate to `scout`.
- NEVER have the Main Agent implement multi-file changes directly; ALWAYS partition and delegate to subagents.
- NEVER yield or serialize work when independent chunks can run concurrently in a single `tasks[]` batch.

### Subagent Role Directory
- `scout`: Read-only rapid exploration, codebase mapping, cross-directory search, and handoff summaries.
- `reviewer`: Code review, quality evaluation, architectural consistency, and convention compliance.
- `security-reviewer`: Read-only security audit, vulnerability scanning, and risk assessment.
- `architect`: System architecture design, implementation planning, and module decomposition.
- `plan-reviewer`: Independent review and gate approval of technical plans (`plan.md`).
- `sonic`: High-speed, focused mechanical edits and quick transformations.
- `dely-implementer`: Autonomous coding, TDD, task implementation following design contracts.
- `dely-reviewer`: Independent code review, reproduction of test gates, and counterexample evaluation.
- `docs-reader` / `docs-fact-check` / `docs-reviewer` / `docs-update` / `docs-init`: Full lifecycle management of Spec-Driven documentation.

### Multi-Agent Dynamic Spawning & Concurrency
- **Eager Parallel Decomposition:** When facing multi-file analysis, cross-subsystem investigations, broad reviews, or independent implementation chunks, dynamically spawn multiple subagents in parallel via the `task` tool using a single `tasks[]` batch instead of executing sequentially.
- **Workload Partitioning:** Fan out work across specialized agents based on task domains (e.g., spawn several `scout` agents scoped to different directories/modules, alongside a `reviewer` or `docs-*` agent).
- **Avoid Bottlenecks:** Do not serialize independent exploration or tasks that can be delegated to ≥ 2 concurrent workers. Coordinate shared resources or downstream integration only after parallel batch completion.

### Advisor Role Guidelines
- When acting as **Advisor**: Provide passive analysis, architectural critique, edge-case risks, and suggestions only. NEVER issue mutation tool calls (`write`, `edit`, `bash` state changes). Output purely analytical feedback.

## Workspace

Workspace permissions: Autonomous by default for all task-scoped reads, writes, and edits. No confirmation required for standard code changes. Explicit confirmation is required ONLY for Risky Operations: destructive actions (data loss, force push, dropping tables/branches, hard resets, deleting production assets).

---

## Git Worktrees

Allowed only when requested or for approved parallel chunks. Use the exact task/chunk name. No parallel worktree agents unless requested. Delete each worktree only after completion, verification, and merge; leave none orphaned.

---

## Tools

### MCP Routing & Strict Enforcement (Hard Constraints)
- **Strict OUTPUT PREFIX Verification:** You MUST NEVER issue a tool call without first outputting the `[Pre-flight]` prefix.
- **MCP Route & Priority (Hard Constraints):** BẮT BUỘC ưu tiên dùng các MCP tools chuyên dụng tương ứng với domain của task (ví dụ: dùng MCP tool về code graph thay vì `grep`, dùng MCP tool về browser thay vì `curl`/`wget`, dùng MCP tool về database/memory thay vì tra cứu file thủ công). **CẤM** lạm dụng `bash` (grep, find, awk, curl) hoặc native tools khi trong danh sách công cụ đã có MCP tool phục vụ chức năng đó.
- **Fallback Rule:** Chỉ dùng bash/native tools thay thế khi MCP báo lỗi không khả dụng hoặc user bắt buộc. Lạm dụng bash/grep thay cho MCP là vi phạm nghiêm trọng.

- Use local search/read/terminal and external docs for third-party integrations as needed.
- Don't assume optional tools/services exist; fall back gracefully and report limitations.
- Prefer focused searches/ranges/summaries over entire massive logs or files.

---

## Windows Shell

Prefer PowerShell 7 (`pwsh`); use other shells only when required. Run heavy tasks sequentially in small steps. Set timeouts for long commands; inspect or stop safely if exceeded.

---

## Java

Before build/compile, detect the project JDK and set `JAVA_HOME`; don't rely on machine default unless it matches. Store the JDK/project mapping when memory is available.

---

## Reporting

For bugs, investigations, incidents, or complex tasks: **Current Status, Root Cause, Resolution, Impact, Risks, Next Step**. For simple tasks: what changed, verification, remaining risk. Always report blockers and incomplete verification.

---

## Estimate, Monitor, and Verify

For standard CLI commands, builds, and unit tests, execute directly with an appropriate timeout. Reserve structured estimate-and-monitor tracking strictly for long-running asynchronous background jobs (> 3 minutes) or unverified long scripts:

1. Before starting, state the shortest accurate estimate without buffer, set a timeout if supported, and schedule a check at the deadline.
2. At each check: stop safely and report if failed/stalled/not progressing; otherwise give a new shortest estimate and schedule the next check.
3. Verify the real result before claiming success. Never use `sleep` or continuous polling, or leave a task blocking the agent queue.

Background tasks must be finite and non-interactive. Commands that stay open or run continuously (servers, watchers, log streams) must run in a separate system terminal, never an agent background task.
