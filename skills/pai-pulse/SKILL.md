---
name: pai-pulse
description: POST to PAI canonical Pulse daemon on 127.0.0.1:31337 for TTS notifications via ElevenLabs SDK encapsulated server-side. Use when user says notify, tell me when, mobile push, voice alert, send a notification, or wants asynchronous voice delivery from a long-running task.
---

# pai-pulse skill

## When to use

User wants:
- TTS notification ("notify me", "tell me", "voice alert me")
- Mobile push ("send to my phone", "push to telegram") — Pulse routes to mobile via Tailscale
- Async alert from long task ("ping me when ralph finishes")
- Hourly digest, cron-driven mobile messages

## Endpoint

```
POST http://127.0.0.1:31337/notify
Content-Type: application/json
Body: {"message": "<text>"}
```

Response: `{"status": "success", "message": "Notification sent"}` on success.

Pulse handles:
- ElevenLabs SDK call (TTS synthesis)
- Push routing to mobile via Tailscale Serve PRIVATE
- Display in Pulse dashboard at `https://<vps>.<tailnet>.ts.net/pulse`

## Command — MANDATORY

**Always invoke via `bin/pai-pulse-send`** — never call curl directly for Pulse notifications.
`pai-pulse-send` is the only sanctioned entrypoint: it validates the URL is loopback-only,
validates message length, and builds the JSON body via `jq --arg` so that any injected
shell metacharacters (`$(...)`, backticks, `${...}`) are passed as literal text instead of
executing.

```bash
pai-pulse-send --message "<message text>" [--title "<title>"]
```

With a custom URL (overrides `$PAI_PULSE_URL`):

```bash
pai-pulse-send --message "<message text>" --url http://127.0.0.1:31337
```

## Safety — JSON construction

`pai-pulse-send` builds the JSON body with:

```bash
jq -n --arg msg "$MSG" --arg title "$TITLE" '{message: $msg, title: $title}'
```

`jq --arg` treats every value as opaque data — quotes, `$()`, backticks, backslashes are all
escaped for JSON and never re-evaluated by the shell. The wrapper also refuses any non-loopback
URL (exit 77) so Pulse can never be redirected to an external host.

**Discouraged — do not use raw curl for Pulse notifications:**

```bash
# WRONG — string interpolation executes metacharacters:
curl ... -d "{\"message\":\"$user_text\"}"

# WRONG — still expands $() inside double quotes:
curl ... -d "$(jq -n --arg m "$user_text" '{message:$m}')"
```

Use `pai-pulse-send` instead.

## Execution

Via Hermes `terminal` toolset. Pulse is loopback-only — no network risk.

If Pulse unreachable (probe via `pai-doctor` skill first), fall back to:
1. Hermes native TTS provider (`config.yaml` voice config: ElevenLabs, Aria, neutts, voxtral).
2. `notify-send` (Linux desktop notification, no voice).
3. Telegram bot message (Hermes gateway).

## Inputs

- `message` (required) — text to synthesize. Plain text, no markdown. Max ~200 chars for natural prosody.
- `title` (optional) — short label, passed as JSON field.
- `--url` (optional) — override `$PAI_PULSE_URL` (must still be loopback).

## Caveats

- Pulse on **Linux VPS** may not run by default (PAI canonical Pulse is macOS launchd). Verify via `pai-doctor`.
- ElevenLabs SDK requires API key configured in PAI canonical install. No key → TTS fails silently.
- Loopback only — never expose `/notify` publicly. Mobile push happens via Pulse's own routing, not direct from external.
- `pai-pulse-send` enforces max 4096-byte messages; keep notifications concise.

## Cost

- ElevenLabs charge per character synthesized — keep messages concise.
- Pulse caches identical messages briefly — repeat same alert won't re-bill.

## Triggers in Hermes natural language

- "notify me when this is done" → wrap final result in pai-pulse-send call
- "voice my last commit message" → `git log -1 --pretty=%s` → pai-pulse-send
- "tell me on my phone X" → pai-pulse-send → Pulse routes to mobile
- "alert me at 17:00 to check the deploy" → Hermes cron + pai-pulse-send

## Example invocation from skill chain

After `omc ralph` finishes:
```bash
pai-pulse-send --message "Ralph completed: 3 tests fixed, 1 file modified."
```

User hears via mobile within seconds.
