# ARCHITECTURE — pai-hermes bridge

## Why this exists

User has 4 capable systems installed:

1. **Hermes Agent** (Nous Research) — primary daily AI agent. Python, multi-model, multi-platform, sandboxes, cron, FTS5 memory, local Whisper STT, ElevenLabs/Aria/neutts TTS, agent-curated learning loop. ~5× the surface of any custom router.
2. **pai-anywhere** — VPS install socle. Tailscale Serve PRIVATE, HMAC pairing, gateway proxy, doctor, dedicated `pai` user, manifest-driven rollback.
3. **PAI canonical** (Daniel Miessler) — Pulse daemon, 22 routes, ElevenLabs voice provider, Algorithm v6.3, 45 skills (OSINT, RedTeam, Science, SystemsThinking, Telos, …), Memory v7.6, CostTracker with leak detection, statusline tracking 5h/7d Claude usage windows.
4. **OMC** (`oh-my-claudecode`) — Claude Code harness with ralph/team/autopilot/ultrawork orchestration, 29 agents, hooks system.

The four systems don't know about each other:
- Hermes doesn't know PAI skills exist
- Hermes doesn't know OMC's ralph/team commands
- Nothing auto-watches upstream changes across all 4
- No SHA-pinning rollback for PAI ecosystem
- PAI statusline only visible in Claude Code session (not in Hermes TUI)

`pai-hermes` = the **30% bridge** that wires Hermes into PAI ecosystem awareness.

## Predecessor

A sibling repo `pai-projet/` (session-output bash router, 540 LOC) tried to be the unified entrypoint. `/simplify` revealed it overlapped Hermes 70%. Decision: retire `pai-projet`, replace with this thinner bridge.

## Diagram

```
                  laptop · phone · TUI · Telegram · Discord
                          │
                          ▼
              ┌──────────────────────────────┐
              │ Hermes Agent (Python)        │
              │  - 200+ models               │
              │  - voice STT/TTS native      │
              │  - FTS5 + Honcho memory      │
              │  - built-in cron             │
              │  - sandboxes (7 backends)    │
              │  - external_dirs skill load  │
              └──────────────────────────────┘
                          │
        ┌─────────────────┼────────────────────────┐
        ▼                 ▼                        ▼
   skill loader        cron scheduler          terminal toolset
        │                 │                        │
        ▼                 ▼                        ▼
   pai-hermes/skills  pai-hermes/cron        invokes external CLIs
   ├─ omc             ├─ pai-watch (1h)       ├─ omc (Claude Code)
   ├─ pai-pulse       ├─ pai-cost-tracker     ├─ curl Pulse /notify
   ├─ pai-watch       │   (1h)                ├─ git fetch
   ├─ pai-doctor      └─ pai-statusline-      └─ jq paths.env
   ├─ pai-accept           banner (18:00)
   ├─ pai-cost-tracker
   ├─ pai-statusline-banner
   └─ (PAI canonical Packs/ via external_dirs)
        │
        ▼
   45 PAI skills (OSINT, Telos, Science, RedTeam, ...)

                          ▼ host side
              ┌──────────────────────────────┐
              │ VPS — pai-anywhere socle     │
              │  - Tailscale Serve PRIVATE   │
              │  - HMAC pairing + gateway    │
              │  - dedicated pai user        │
              │  - install manifest          │
              └──────────────────────────────┘
                          │
              ┌───────────┴─────────────┐
              ▼                         ▼
        PAI canonical             oh-my-claudecode
        (Pulse 31337,             (Claude Code harness)
         ElevenLabs,
         Algorithm, skills)
```

## Design principles

### 1. Composition, never modification

`pai-hermes` adds **only**:
- 7 SKILL.md files
- 3 cron yaml files
- 1 Python helper (`cost_check.py`)
- 1 install.sh that edits `~/.hermes/config.yaml` additively

Never modifies:
- Hermes Agent source
- PAI canonical source (Miessler-owned)
- OMC source
- pai-anywhere source

### 2. Skills describe intent, not impl

Each SKILL.md tells Hermes *when* + *what command* to run. No Python tool wraps OMC — Hermes already has `terminal` and `code_execution` toolsets that execute shell. Skill body = routing decision logic in natural language.

Exception: `pai-cost-tracker` ships `tools/cost_check.py` because PAI usage cache JSON parsing is non-trivial and needs typed thresholds.

### 3. Cost discipline

| Path | AI cost |
|------|---------|
| Cron jobs (pai-watch / pai-cost-tracker / pai-statusline-banner) | ZERO. Pure data aggregation. |
| User-triggered (omc / pai-pulse / pai-accept / pai-doctor) | Variable. `omc ralph/team/autopilot` are HIGH cost. |

`pai-cost-tracker` gates high-cost OMC invocations. If 5h window >85%, OMC skill refuses to launch ralph/team/autopilot until reset.

### 4. Security model

- `pai-accept` SSH-only. Never callable from remote platform (TG/Discord/Signal/WA). Plan v5 §13 ADR enforced.
- No new Pulse routes added (composition rule + Miessler's launchd is fixed).
- pai-anywhere gateway exposes ONLY `/proposals/<id>` GET read-only (POST/DELETE return 405).
- Voice alerts respect quiet hours config to avoid 3am wake-ups.

### 5. Single source of truth

| Domain | Owner | Path |
|--------|-------|------|
| Claude usage 5h/7d % | PAI canonical | `~/.claude/PAI/MEMORY/STATE/usage-cache.json` |
| API cost ledger | PAI canonical | `~/.claude/PAI/MEMORY/OBSERVABILITY/anthropic-cost.jsonl` |
| Sub-project SHA pins | pai-hermes (via pai-accept) | `/etc/pai/paths.env` |
| Proposals | pai-hermes (via pai-watch) | `/var/lib/pai-anywhere/proposals/*.json` |
| Pulse notify queue | PAI canonical Pulse daemon | `127.0.0.1:31337/notify` |
| Hermes agent memory | Hermes | `~/.hermes/state.db` |
| Hermes session FTS5 | Hermes | `~/.hermes/sessions/` |
| arc review markdown | pai-collab | `pai-collab/projects/arc/reviews/` |

No duplication. Each skill reads from one canonical source.

### 6. Failure modes are documented

Every skill's body includes a `Caveats` section listing known failure paths + fallback behavior:
- Pulse unreachable → fallback to Hermes native TTS providers
- arc dir absent → skip markdown write, paths.env update still happens
- `arecord` absent (headless server) → voice STT skill returns 78
- Whisper.cpp not built → cost tracker still works (cache read), voice STT degrades
- Usage cache stale (>15 min old) → cost-tracker emits warning in output

## Boundary with pai-projet (sibling repo)

`pai-projet` (540 LOC bash session output) overlaps this repo on 5 of 11 commands. After pai-hermes 0.1.0 wired and verified:

| pai-projet command | Replacement |
|--------------------|-------------|
| `pai ask` | Hermes native (any model) |
| `pai voice` | Hermes ctrl+b (local Whisper) |
| `pai notify` | pai-pulse skill |
| `pai watch run` | pai-watch skill + Hermes cron |
| `pai accept` | pai-accept skill (SSH-only) |
| `pai proposals list` | pai-watch skill output dir read |
| `pai paths show/pin` | pai-accept internals + manual edit |
| `pai metrics` | Hermes own session metrics + pai-cost-tracker |
| `pai logs` | Hermes audit log + ~/.hermes/logs |
| `pai doctor` | pai-doctor skill |
| `pai help/version` | Hermes built-in |

After pai-hermes proves out for ~2 weeks, archive `pai-projet` (GH read-only, preserve git history).

## Maintenance posture

| Frequency | Action | Owner |
|-----------|--------|-------|
| Weekly | Review pai-watch proposals queue | User (SSH) |
| Weekly | Read pai-statusline-banner Friday digest | User (mobile) |
| Monthly | Check ANTHROPIC API spend vs subscription bypass | User (or PAI CostTracker scan) |
| On Hermes config schema change | Patch install.sh + regenerate `external_dirs` block | pai-hermes contributor |
| On PAI canonical v6+ (if usage-cache.json schema changes) | Update `tools/cost_check.py` field extraction | pai-hermes contributor |
| On OMC v5+ (if CLI surface changes) | Update `skills/omc/SKILL.md` command table | pai-hermes contributor |

Target: ≤30 min/month maintenance for the bridge itself.

## Future evolutions (0.2.0+)

Documented in CHANGELOG `[Unreleased]`:
- Hermes TUI statusline port (Python equivalent of PAI bash statusline).
- `pai-skill-discover` auto-loader for PAI Packs.
- `pai-telos-bridge` exposing TELOS to Hermes memory.
- `pai-algorithm-v6.3` skill routing through OBSERVE/THINK/PLAN/ACT/VERIFY/REFLECT phases.
- Platform-specific helpers for Telegram/Discord routing of pai-pulse messages.

Out of scope permanently:
- Modifying Hermes / PAI canonical / OMC sources.
- Bundling models or binaries (Whisper, ElevenLabs SDK).
- Adding new Pulse routes (Miessler boundary).
- Multi-tenant gateway ACL (single-user assumption per pai-anywhere v0.2.0).
