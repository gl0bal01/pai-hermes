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
- Automated via cron (default: hourly) — see `cron/README.md` (Hermes jobs.json registration)

## Algorithm

For each repo in `PAI_WATCH_SOURCES` (default 4):

1. Validate repo name and resolve path (see **Repo validation** below).
2. `GIT_CONFIG_GLOBAL=/dev/null git -C <repo-dir> fetch --quiet origin`
3. Compare `HEAD` vs upstream tracking branch (e.g. `origin/main`).
4. If diverged, get commit log `GIT_CONFIG_GLOBAL=/dev/null git -C <repo-dir> log --pretty="%h %s" HEAD..origin/main`.
5. Compute impact score (0-100):
   - `+5` per new commit
   - `+25` per commit subject matching `\b(breaking|major|incompatible|drop|remove)\b` (case-insensitive)
   - `+15` per commit touching critical paths: `src/cli/`, `Algorithm/`, `Pulse/`, `install.sh`, `paths.env`
   - Cap at 100.
6. If score ≥ `PAI_WATCH_THRESHOLD` (default 10):
   - Ensure the output dir exists (`mkdir -p "$PAI_PROPOSALS_DIR"`), then write the
     JSON proposal to `$PAI_PROPOSALS_DIR/<id>.json` (id = `<ISO-ts>-<repo>`).
   - Notify via `pai-pulse-send --message "<alert text>"`.
7. Else log and skip.

## Repo validation

**Before running any git command**, each repo name from `PAI_WATCH_SOURCES` must be validated:

```bash
PAI_PROJET_ROOT="${PAI_PROJET_ROOT:-/opt/pai-projet}"

for repo in $PAI_WATCH_SOURCES; do
  # 1. Name must match safe pattern — no slashes, dots-only, flag-like strings.
  if [[ ! "$repo" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "pai-watch: skipping unsafe repo name: $repo" >&2
    continue
  fi

  # 2. Resolved path must stay under PAI_PROJET_ROOT (no traversal).
  repo_path="$(realpath -m "${PAI_PROJET_ROOT}/${repo}" 2>/dev/null || echo "")"
  root_real="$(realpath -m "${PAI_PROJET_ROOT}" 2>/dev/null || echo "${PAI_PROJET_ROOT}")"
  case "${repo_path}/" in
    "${root_real}/"*) ;;
    *) echo "pai-watch: path traversal refused for: $repo" >&2; continue ;;
  esac

  # 3. Run git with a neutralized global config to prevent hostile hook injection.
  GIT_CONFIG_GLOBAL=/dev/null git -C "$repo_path" fetch --quiet origin
  # ... rest of per-repo logic
done
```

`GIT_CONFIG_GLOBAL=/dev/null` prevents a crafted `~/.gitconfig` (or a repo-local
`core.hooksPath` inherited from global config) from executing arbitrary commands during fetch.

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
| `PAI_WATCH_SOURCES` | `"oh-my-claudecode Personal_AI_Infrastructure pai-anywhere pai-review-mode"` | Space-separated repo dir names under `$PAI_PROJET_ROOT`. `install.sh` narrows this to the repos that actually exist on the host and writes the result to `$HERMES_HOME/pai-hermes.env`. |
| `PAI_PROJET_ROOT` | `/opt/pai-projet` | Root holding all sub-project clones. The default rarely matches a real host, so `install.sh` auto-detects it (the parent of the pai-hermes checkout) and persists it to `$HERMES_HOME/pai-hermes.env`. |
| `PAI_PROPOSALS_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/pai-hermes/proposals` | Output dir. Defaults under the Hermes user's state dir so the gateway can always write it; created on demand. |
| `PAI_WATCH_THRESHOLD` | `10` | Min impact score to propose |
| `PAI_PULSE_URL` | `http://127.0.0.1:31337` | Pulse for notify |

## Cron entry

Register via Hermes — see `cron/README.md`. Job is stored in `~/.hermes/cron/jobs.json`:

```json
{ "name": "pai-watch", "schedule": { "kind": "cron", "expr": "0 * * * *" }, "skill": "pai-watch" }
```

## Cost

ZERO AI cost. Pure `git fetch` + bash regex. No model invocation.

## Caveats

- Requires `git fetch` write access (HTTPS or SSH) for each source repo.
- Network failure on one repo doesn't block others (per-repo try/catch).
- If `PAI_PROPOSALS_DIR` not writable, proposal silently skipped — verify via `pai-doctor` skill.
- Pulse `/notify` failure is non-fatal — proposal still written to disk.
- Repo names with `..`, leading `-`, or characters outside `[A-Za-z0-9._-]` are skipped.

## Skill chain

`pai-watch` → writes proposals → calls `pai-pulse-send` to push mobile alert.
User then runs `pai-watch list` or `pai-accept <id>` to SHA-pin a proposal.
