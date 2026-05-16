---
name: omc
description: oh-my-claudecode (OMC) harness — Claude Code orchestration. Use when user says ralph, team, autopilot, ultrawork, ultrapilot, or wants Claude Code session with hooks/skills/agent catalog. Routes to local `omc` CLI binary.
---

# OMC harness skill

## When to use

User says or implies:
- "ralph" → sequential persistence loop until task done with verification
- "team" → spawn N coordinated agents on shared task list
- "autopilot" → full autonomous execution from idea to working code
- "ultrawork" → high-throughput parallel task completion
- "ultrapilot" → autopilot + ultrawork combination
- "claude code session", "use claude code", "interactive claude" → `omc launch`
- "ask claude about X" with code context → `omc ask claude -p "X"`
- "deepinit", "deepsearch", "deep interview" → OMC skill triggers

## Commands

| Intent | Command | Cost class |
|--------|---------|------------|
| Sequential persistence loop | `omc ralph "<task>"` | HIGH |
| Parallel coordinated agents | `omc team N:executor "<task>"` | HIGH |
| Autonomous build | `omc autopilot "<task>"` | HIGH |
| High-throughput parallel | `omc ultrawork "<task>"` | HIGH |
| Provider advisor prompt | `omc ask claude -p "<prompt>"` | LOW |
| Interactive TUI | `omc launch` | INTERACTIVE |
| Diagnose OMC install | `omc doctor` | FREE |
| Show version | `omc --version` | FREE |
| Configure stop callbacks | `omc config-stop-callback <type>` | FREE |
| Session inspection | `omc session list` | FREE |

## Execution

Run via Hermes `terminal` / `code_execution` toolset. Working directory defaults to user's project root (allow override via `cwd:` arg in skill invocation).

Pre-flight: ensure `omc --version` returns ≥4.13.7. If absent:
```bash
npm install -g oh-my-claudecode
# or
bun install -g oh-my-claudecode
```

## Environment

OMC subprocess MUST run with:
- `HOME=/home/pai` (or wherever PAI canonical lives on VPS)
- `CLAUDE_CONFIG_DIR=$HOME/.claude`

This ensures PAI statusline + UpdateCounts.hook + Spinner assets resolve. Without these, OMC launches a vanilla Claude Code session without PAI integration.

## Output handling

- `version`, `doctor`, `ask` (non-streaming): capture full stdout, return to Hermes context.
- `ralph`, `team`, `autopilot`, `ultrawork`: streaming. Use `code_execution_tool` streaming mode if Hermes config allows. Otherwise tail output file.
- `launch`: interactive — spawn in tmux pane or sandbox terminal. Do not block Hermes main loop.

## Cost discipline

`ralph`, `autopilot`, `team`, `ultrawork` burn Claude API tokens at scale (multi-agent, multi-turn). Confirm with user before launching when task scope >5 files OR estimated duration >30 min.

If `pai-cost-tracker` reports 5h window >80%, **refuse to launch high-cost OMC commands** until window resets or user explicitly overrides.

## Caveats

- `omc ralph` may run for hours. Show progress via tail or skill chain to `pai-pulse` for completion notification.
- `omc team` spawns subagents that consume tokens independently of main agent.
- OMC native rate_limits read from Claude OAuth — same usage cache `pai-cost-tracker` reads.
- Mutations made by OMC are NOT auto-recorded in `pai-anywhere` install manifest.

## Triggers in Hermes natural language

- "ralph the test failures" → `omc ralph "fix failing tests"`
- "spawn a team of 3 to refactor auth" → `omc team 3:executor "refactor auth module"`
- "build me X with autopilot" → `omc autopilot "<X>"`
- "claude opinion on this commit" → `omc ask claude -p "review HEAD commit"`
