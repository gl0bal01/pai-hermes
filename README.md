# pai-hermes

> Bridge skills + cron jobs that make [Hermes Agent](https://github.com/NousResearch/Hermes-Agent) PAI-ecosystem-aware. Replaces 540 LOC of pai-projet bash with native Hermes skills.

**Status**: v0.1.3 (2026-06-19). Skills wired; cron registered via Hermes jobs.json.

## What it does

Plugs **Hermes** into the **PAI ecosystem** (OMC, pai-anywhere, PAI canonical):

- Route `omc ralph/team/autopilot/...` from Hermes TUI / Telegram / Discord
- Trigger Pulse `/notify` TTS for mobile alerts
- Auto-watch upstream changes across 4 PAI repos, propose human-gated bumps
- Track Claude 5h/7d subscription usage + voice-alert when approaching limit
- Daily cost/wellness banner pushed to mobile
- PAI ecosystem health probes (`pai-doctor` style)

## 7 skills

| Skill | What | When triggered |
|-------|------|----------------|
| `omc` | Route to OMC harness CLI | "ralph", "team", "autopilot", "ultrawork", Claude Code session needed |
| `pai-pulse` | POST to Pulse `/notify` (ElevenLabs TTS) | "notify", "tell me when", mobile push |
| `pai-watch` | Fetch + impact-score 4 upstream repos | Hourly cron + on-demand "check upstream" |
| `pai-doctor` | PAI infra health probes (Pulse, Tailscale, paths, statusline) | "doctor", "is everything ok" |
| `pai-accept` | SHA-pin proposal in `paths.env` + arc review | SSH-only after `pai-watch` proposes |
| `pai-cost-tracker` | Read 5h/7d usage cache + voice alert on threshold | Hourly cron + on-demand "usage" |
| `pai-statusline-banner` | Daily digest of 5h/7d/leaks → mobile push | Daily 18:00 cron |

## Install

```bash
git clone https://github.com/gl0bal01/pai-hermes ~/.hermes/pai-hermes
cd ~/.hermes/pai-hermes
./install.sh    # edits ~/.hermes/config.yaml + symlinks cron/ + tests skills
```

See [docs/INSTALL.md](docs/INSTALL.md) for full walkthrough including pai-anywhere VPS deploy.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
Hermes (Python agent, 200+ models, multi-platform)
   │
   ├── external_dirs += pai-hermes/skills/  ── 7 SKILL.md routes
   ├── external_dirs += PAI canonical Packs/ ── 45 PAI skills (OSINT, Telos, RedTeam, ...)
   ├── cron: pai-watch hourly                ── upstream watcher
   ├── cron: pai-cost-tracker hourly         ── usage guardrail + voice alert
   └── cron: pai-statusline-banner daily     ── mobile digest

   └── invokes via terminal toolset:
        - omc CLI (Claude Code harness)
        - Pulse /notify (PAI canonical, port 31337 loopback)
        - git fetch (upstream watch on 4 repos)
        - Pulse-Anywhere gateway (mobile preview /proposals/<id>)
```

## Why this exists

`pai-projet` (sibling repo, session output) built 540 LOC bash router. Then `/simplify` revealed Hermes already does 70% of it natively. This bridge is the remaining **30% of glue** Hermes needs to know about PAI.

End state: Hermes = daily agent. pai-hermes = the awareness layer. pai-projet bash retired.

## Sibling repos

| Repo | Role |
|------|------|
| `Hermes-Agent` | Primary daily agent (Nous Research, MIT) |
| `pai-anywhere` | VPS install socle (Tailscale, HMAC pairing, gateway) |
| `Personal_AI_Infrastructure` | PAI canonical (Pulse, 45 skills, Algorithm v6.3, ElevenLabs voice) |
| `oh-my-claudecode` (OMC) | Claude Code harness invoked by `omc` skill |
| `pai-collab` | `arc` registry — markdown sink for accepted upstream reviews |

## Tests

```bash
bats tests/skill-format.bats   # validates SKILL.md frontmatter on all 7 skills
```

## License

MIT.

## Status caveats

- 0.1.0 = scaffold only. Skills compose Hermes invocations but live wiring needs VPS testing.
- `pai-cost-tracker` reads `~/.claude/PAI/MEMORY/STATE/usage-cache.json` — requires PAI canonical install.
- `pai-watch` cron requires 4 source repos cloned at paths in `~/.hermes/config.yaml`.
