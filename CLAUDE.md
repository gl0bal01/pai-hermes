# pai-hermes — Agent briefing

> Build-time briefing for AI agents working on this repo. Read before touching skill content.

**Phase**: v0.1.3 (2026-06-19).

## Mission

Make Hermes Agent PAI-ecosystem-aware via 7 skills + 3 cron jobs. Replace `pai-projet/bin/pai` bash router (540 LOC) with Hermes-native routing. Keep PAI canonical, OMC, pai-anywhere untouched.

## Scope

### In scope
- 7 SKILL.md files (markdown only, no Python tools required for MVP).
- 3 Hermes cron jobs (registered via Hermes into jobs.json — see cron/README.md).
- `install.sh` that edits `~/.hermes/config.yaml` (`skills.external_dirs` + cron registration).
- 1 optional Python helper (`tools/cost_check.py`) for cost-tracker skill.
- bats test validating SKILL.md frontmatter.

### Out of scope
- Modifying Hermes Agent source.
- Modifying PAI canonical source.
- Modifying OMC source.
- Custom Hermes plugin (Python module).
- Hermes TUI statusline port (separate effort).

## Hard constraints

| Constraint | Rule |
|---|---|
| Skill format | Frontmatter (`name`, `description`) + body. agentskills.io compatible. |
| Skill body | Markdown only. No code execution from skill — only describes intent + commands. |
| Hermes integration | Read-only: skill points Hermes at existing tools (terminal, code_execution, delegate, voice). |
| External dirs | Append, never replace. Preserve user's existing `external_dirs:`. |
| Cron | Use Hermes's built-in cron scheduler. Never deploy systemd timers. |
| Auth | `pai-accept` requires a real SSH session — enforced by `sshd` process-ancestry (not the spoofable `SSH_*` env), so it is never callable via Pulse, gateway, or a remote-platform-driven Hermes. Tailscale SSH satisfies it from anywhere; non-SSH break-glass is a root-owned `/etc/pai/local-accept.allow`. |
| Cost | Subscription-first. `pai-cost-tracker` warns when API spend approaches threshold. |
| Composition | Never modify sub-projects (PAI canonical, OMC, pai-anywhere, Hermes). Glue only. |

## Working rules

- Each SKILL.md ≤120 LOC. Concise. Trigger phrases + intent + commands + caveats.
- Skills MAY recommend chaining to other skills via prose hints in their body (e.g. "after this, call pai-pulse to notify"). The agent — Hermes — decides whether to honor the hint. Skills do NOT directly invoke each other (no sub-process call between skills). Chains form a directed acyclic graph: pai-watch → pai-pulse, pai-cost-tracker → pai-pulse, pai-statusline-banner → {pai-doctor, pai-cost-tracker, pai-pulse}. No cycles. Hermes is always the orchestrator; skills are leaves.
- Cron files match Hermes built-in scheduler format (see `~/.hermes/cron/`).
- `install.sh` is idempotent — re-run safely.
- Changes to skill content do NOT require Hermes restart unless skill cache is on (check `~/.hermes/config.yaml`).
- Cost-sensitive skills (`omc`, `pai-cost-tracker`) MUST include cost warnings in body.

## Layout

```
pai-hermes/
├── README.md
├── LICENSE                                  # MIT
├── CLAUDE.md                                # this file
├── CHANGELOG.md
├── install.sh                               # idempotent installer
├── uninstall.sh                             # reverse install
├── skills/
│   ├── omc/SKILL.md                         # Claude Code harness routing
│   ├── pai-pulse/SKILL.md                   # /notify TTS
│   ├── pai-watch/SKILL.md                   # upstream watcher
│   ├── pai-doctor/SKILL.md                  # PAI ecosystem health probes
│   ├── pai-accept/SKILL.md                  # SHA pin SSH-only
│   ├── pai-cost-tracker/SKILL.md            # 5h/7d usage guardrail + voice alert
│   └── pai-statusline-banner/SKILL.md       # daily mobile digest
├── tools/
│   └── cost_check.py                        # optional helper for cost-tracker
├── cron/
│   └── README.md                            # job registration instructions (jobs.json via Hermes)
├── tests/
│   └── skill-format.bats                    # validates frontmatter
└── docs/
    ├── INSTALL.md                           # VPS deploy steps
    └── ARCHITECTURE.md                      # bridge design
```

## Composition rule

| Source | Don't touch | License |
|--------|-------------|---------|
| `~/.hermes/hermes-agent/` | Hermes Agent itself | MIT |
| `Personal_AI_Infrastructure/` | PAI canonical | MIT |
| `oh-my-claudecode/` (OMC) | OMC source | MIT |
| `pai-anywhere/` | Install socle | MIT |
| `pai-collab/` | arc registry | **AGPL-3.0** |

## AGPL boundary

`pai-collab` is AGPL-3.0. `pai-hermes` is MIT. To prevent AGPL contagion, the bridge MUST observe:

- **Allowed**: `pai-accept` writes its own MIT-licensed markdown files INTO `pai-collab/projects/arc/reviews/*.md`. Filesystem write only. Equivalent to making a git commit to an AGPL repo — content flows in, AGPL stays in pai-collab.
- **Forbidden**: embedding pai-collab source files in pai-hermes (would make pai-hermes derivative work → AGPL).
- **Forbidden**: linking pai-collab Python/Node modules as libraries in pai-hermes tools (derivative work → AGPL).
- **Forbidden**: running pai-collab code as a network service via pai-hermes (AGPL §13 triggers).
- **Forbidden**: copying pai-collab text content (CONTRIBUTING.md, JOURNAL.md, etc.) into pai-hermes docs.

If pai-collab ever becomes a code dependency (not just a markdown sink), pai-hermes MUST relicense to AGPL-3.0 OR drop the dependency.

`pai-hermes/` adds files to:
- `~/.hermes/skills/pai-hermes/*` (symlinks or copies)
- `~/.hermes/cron/*.yaml`
- `~/.hermes/config.yaml` (additive only)

## Cost discipline

- Cron jobs MUST be zero-AI-cost — pure data aggregation (no LLM calls).
- `pai-watch` uses `git fetch` + regex impact-score. No model invocation.
- `pai-cost-tracker` reads existing PAI usage cache JSON. No model invocation.
- `pai-statusline-banner` aggregates JSONL + posts via Pulse. No model invocation.
- LLM-invoking skills (`omc`, `pai-pulse` content) only trigger on user request.

## References

- Hermes config schema: `~/.hermes/config.yaml`
- Hermes skill loader: `~/.hermes/hermes-agent/skills/` Python loader (TBD)
- PAI canonical statusline: `Personal_AI_Infrastructure/Releases/v5.0.0/.claude/PAI/statusline-command.sh`
- PAI CostTracker: `Personal_AI_Infrastructure/Releases/v5.0.0/.claude/PAI/TOOLS/CostTracker.ts`
- OMC CLI: `omc --help` → 18+ subcommands
- Pulse routes: `Personal_AI_Infrastructure/Releases/v5.0.0/.claude/PAI/PULSE/setup.ts`
- pai-projet plan (predecessor): `../.omc/plans/pai-global-unification-strategy.md`
