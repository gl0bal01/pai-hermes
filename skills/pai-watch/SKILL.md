---
name: pai-watch
description: Hourly upstream watcher for 4 PAI ecosystem repos (oh-my-claudecode, Personal_AI_Infrastructure, pai-anywhere, pai-review-mode). Fetches origin, computes impact score, writes JSON proposal to disk, posts mobile alert via pai-pulse. Use when user says check upstream, watch repos, what changed, upstream bump, propose upgrade.
---

# pai-watch skill

## When to use

User intent:
- "check upstream for X" → manual one-shot watch
- "what changed in PAI / OMC this week" → recent commits summary
- "any upgrades pending" → list active proposals
- Automated via cron (default: hourly) — see `cron/pai-watch.yaml`

## Algorithm

For each repo in `PAI_WATCH_SOURCES` (default 4):

1. `git -C <repo-dir> fetch --quiet origin`
2. Compare `HEAD` vs upstream tracking branch (e.g. `origin/main`).
3. If diverged, get commit log `git log --pretty="%h %s" HEAD..origin/main`.
4. Compute impact score (0-100):
   - `+5` per new commit
   - `+25` per commit subject matching `\b(breaking|major|incompatible|drop|remove)\b` (case-insensitive)
   - `+15` per commit touching critical paths: `src/cli/`, `Algorithm/`, `Pulse/`, `install.sh`, `paths.env`
   - Cap at 100.
5. If score ≥ `PAI_WATCH_THRESHOLD` (default 10):
   - Write JSON proposal to `$PAI_PROPOSALS_DIR/<id>.json` (id = `<ISO-ts>-<repo>`).
   - POST to Pulse `/notify` via pai-pulse skill.
6. Else log and skip.

## Proposal JSON schema

```json
{
  "schema": "pai.proposal.v1",
  "id": "2026-05-16T03-00-00Z-oh-my-claudecode",
  "repo": "oh-my-claudecode",
  "targetSha": "abc1234567890abcdef...",
  "createdAt": "2026-05-16T03:00:00Z",
  "impactScore": 35,
  "commits": "abc1234 feat: new ralph mode\ndef5678 BREAKING: drop legacy hooks",
  "status": "pending"
}
```

## Inputs

| Env var | Default | Purpose |
|---------|---------|---------|
| `PAI_WATCH_SOURCES` | `"oh-my-claudecode Personal_AI_Infrastructure pai-anywhere pai-review-mode"` | Space-separated repo dir names under `$PAI_PROJET_ROOT` |
| `PAI_PROJET_ROOT` | `/opt/pai-projet` | Root holding all sub-project clones |
| `PAI_PROPOSALS_DIR` | `/var/lib/pai-anywhere/proposals` | Output dir |
| `PAI_WATCH_THRESHOLD` | `10` | Min impact score to propose |
| `PAI_PULSE_URL` | `http://127.0.0.1:31337` | Pulse for notify |

## Cron entry

See `cron/pai-watch.yaml`:

```yaml
name: pai-watch
schedule: "0 * * * *"     # hourly
task: "Run pai-watch skill"
```

## Cost

ZERO AI cost. Pure `git fetch` + bash regex. No model invocation.

## Caveats

- Requires `git fetch` write access (HTTPS or SSH) for each source repo.
- Network failure on one repo doesn't block others (per-repo try/catch).
- If `PAI_PROPOSALS_DIR` not writable, proposal silently skipped — verify via `pai-doctor` skill.
- Pulse `/notify` failure is non-fatal — proposal still written to disk.

## Skill chain

`pai-watch` → writes proposals → calls `pai-pulse` to push mobile alert.

User then:
- `pai-watch list` → see pending
- `pai-accept <id>` → SHA-pin proposal (separate skill)

## Bash one-liner equivalent (no skill)

```bash
for repo in oh-my-claudecode Personal_AI_Infrastructure pai-anywhere pai-review-mode; do
  cd /opt/pai-projet/$repo && git fetch -q && \
    git log --pretty='%h %s' HEAD..@{u} 2>/dev/null | \
    awk -v r=$repo 'NF{c++} /(BREAKING|major)/{b++} END{print r, c, b}'
done
```

Skill wraps this with score + proposal writer + notify.
