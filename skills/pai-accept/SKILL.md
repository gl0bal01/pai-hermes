---
name: pai-accept
description: Accept an upstream proposal from pai-watch — pin target SHA in /etc/pai/paths.env + write arc review markdown + mark proposal status=accepted. SSH-only by design (never callable via remote platform). Use when user says accept, approve upgrade, merge proposal, bump, pin sha.
---

# pai-accept skill

## When to use

User intent (must be SSH session):
- "accept proposal X" → pin SHA, write review
- "approve OMC bump" → after pai-watch flagged
- "merge that upstream change" → review-then-pin flow
- NEVER triggered by mobile push / Telegram / Discord — security gate

## Security model

`pai-accept` is the **only mutation** that touches `paths.env`. Plan v5 §13 ADR + pai-anywhere CLAUDE.md require:

1. **SSH-only** — Hermes refuses to run pai-accept if invocation source is not local TTY.
2. **No gateway exposure** — never callable via pai-anywhere gateway proxy.
3. **No Pulse route** — never callable via Pulse HTTP.
4. **No remote platform** — Telegram/Discord/Signal/WhatsApp triggers explicitly rejected.
5. **Audit logged** — every acceptance writes JSONL audit + arc markdown review.

Hermes pre-flight check (in skill body):
```
if [[ -z "$SSH_TTY" && -z "$PAI_LOCAL_OVERRIDE" ]]; then
  echo "pai-accept refused: SSH-only invocation"
  exit 1
fi
```

## Algorithm

1. Read proposal JSON from `$PAI_PROPOSALS_DIR/<id>.json`.
2. Extract `repo`, `targetSha`, `commits` log.
3. Update `/etc/pai/paths.env` (or `$PAI_PATHS_ENV`):
   - Add or replace line `PAI_<REPO>_SHA=<targetSha>` (repo name uppercased with underscores).
4. Write arc review markdown to `pai-collab/projects/arc/reviews/<date>-pai-watch-<repo>-<sha7>.md` (if pai-collab dir present).
5. Update proposal JSON: `.status="accepted"` + `.acceptedAt=<ISO-ts>`.
6. Optional: trigger `pai-pulse` skill to confirm acceptance via voice.

## Inputs

- `proposal_id` (required) — id matching JSON filename in proposals dir.

## Output

```
PAI_<REPO>_SHA=<full-sha>
arc review: <path>
accepted: <id> (<repo> @ <sha7>)
```

## Execution

Via Hermes terminal toolset, SSH-only. If invoked from any non-SSH context, skill MUST refuse and return error.

```bash
# Pre-flight
[[ -n "${SSH_TTY:-}" ]] || { echo "SSH-only"; exit 1; }

# Pin
proposal="$PAI_PROPOSALS_DIR/${ID}.json"
repo=$(jq -r .repo "$proposal")
sha=$(jq -r .targetSha "$proposal")
key="PAI_$(echo "$repo" | tr a-z- A-Z_)_SHA"

# Update paths.env
tmp=$(mktemp)
grep -v "^${key}=" /etc/pai/paths.env > "$tmp"
echo "${key}=${sha}" >> "$tmp"
mv "$tmp" /etc/pai/paths.env

# Mark accepted
jq --arg ts "$(date -u +%FT%TZ)" '.status="accepted" | .acceptedAt=$ts' \
  "$proposal" > "${proposal}.tmp" && mv "${proposal}.tmp" "$proposal"
```

## Rollback

If acceptance was wrong:
```bash
# Restore previous SHA pin via pai-paths skill (separate)
# Or manually:
sed -i '/^PAI_<REPO>_SHA=/d' /etc/pai/paths.env
```

Granular rollback flow (per plan v5 §12):
1. `pai paths pin <repo> <previous-sha>`
2. `pai doctor --strict`
3. Run integration tests
4. If green: commit; if red: revert paths.env

## Caveats

- `/etc/pai/paths.env` requires write perms — typically `pai` user or root.
- `pai-collab/projects/arc/reviews/` is OPTIONAL — skill skips arc markdown if dir absent.
- Acceptance does NOT auto-pull or rebuild the sub-project. User runs `git -C $PAI_<REPO>_DIR checkout $SHA` separately, or uses `pai-anywhere` reinstall flow.
- Sha format validated: must be 40 hex chars OR 7-40 hex chars (allow short SHAs but warn).

## Cost

ZERO AI cost. Pure file ops.

## Triggers in Hermes natural language

- "accept proposal 2026-05-16-...-omc" → run skill with id
- "approve the OMC upstream bump" → list pending proposals first, ask user to confirm id
- NOT triggered by remote message ("accept this from Telegram") — refuse with security explanation
