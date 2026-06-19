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

1. **Real-SSH-session-only** — the guard authorizes only when `sshd` is in the
   invoking process's ancestry (verified via `/proc`, *not* the spoofable
   `SSH_*` env vars). Hermes — a non-root LLM with no `sshd` ancestor — cannot
   pass it, even if prompt-injected. Remote use still works: open a **Tailscale
   SSH** session from any device and the check passes.
2. **No gateway exposure** — never callable via pai-anywhere gateway proxy.
3. **No Pulse route** — never callable via Pulse HTTP.
4. **No remote platform** — Telegram/Discord/Signal/WhatsApp triggers rejected.
5. **Audit logged** — every acceptance writes JSONL audit + arc markdown review.

The boundary is enforced in `bin/pai-accept-guard` (shell), not in this
markdown. Do not reimplement the check inline — invoke the guard (see Execution).
Break-glass for non-SSH local admin/CI is a **root-owned** marker file
(`/etc/pai/local-accept.allow`, mode 0600) that a non-root process cannot forge.

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

**Always invoke the guard wrapper, never the inline commands.** The wrapper enforces SSH-only + flock-based atomicity in shell — markdown rules in SKILL.md are advisory; the guard is the actual security boundary.

```bash
# Canonical invocation:
pai-accept-guard <proposal-id>

# If installed via install.sh, symlink the guard for system-wide use:
sudo ln -sf $PAI_PROJET_ROOT/pai-hermes/bin/pai-accept-guard /usr/local/bin/pai-accept-guard
```

The guard (`bin/pai-accept-guard` in this repo) enforces:

1. **Real-SSH-session-only** — authorizes only when `sshd` is in the process ancestry (forge-resistant; spoofable `SSH_*` env vars are ignored). Exit 77 (EX_NOPERM) otherwise. Local/CI break-glass is a root-owned `/etc/pai/local-accept.allow` (mode 0600), never an env flag.
2. **Input validation** — proposal id, repo name, and SHA must match strict regex. Exit 65 (EX_DATAERR) on mismatch.
3. **flock** — exclusive lock under the user runtime dir (`${XDG_RUNTIME_DIR}/pai-accept/lock`, override via `PAI_ACCEPT_LOCK`) with a 30s timeout (`PAI_ACCEPT_LOCK_TIMEOUT`). Exit 75 (EX_TEMPFAIL) if another accept is in flight.
4. **Atomic paths.env mutation** — write to tmp file (same dir), preserve permissions, then `mv` (atomic on same filesystem).
5. **Atomic proposal status update** — same tmp+mv pattern, prevents partial writes.
6. **Optional arc review** — only if `$PAI_COLLAB_DIR/projects/arc/reviews/` exists and writable. Skipped silently otherwise.

If you really want raw bash inline (NOT recommended — bypasses guard), see source: `bin/pai-accept-guard`.

## Rollback

If acceptance was wrong, invoke the guard with the rollback proposal id — never mutate paths.env directly:

```bash
pai-accept-guard <rollback-proposal-id>
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
