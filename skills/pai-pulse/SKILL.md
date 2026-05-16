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

## Command

```bash
curl -fsS -X POST -H 'content-type: application/json' \
  -d "$(jq -n --arg m "<message>" '{message:$m}')" \
  http://127.0.0.1:31337/notify
```

## Execution

Via Hermes `terminal` toolset. Pulse is loopback-only — no network risk.

If Pulse unreachable (probe via `pai-doctor` skill first), fall back to:
1. Hermes native TTS provider (`config.yaml` voice config: ElevenLabs, Aria, neutts, voxtral).
2. `notify-send` (Linux desktop notification, no voice).
3. Telegram bot message (Hermes gateway).

## Inputs

- `message` (required) — text to synthesize. Plain text, no markdown. Max ~200 chars for natural prosody.
- `priority` (optional, future) — Pulse may accept priority levels.

## Caveats

- Pulse on **Linux VPS** may not run by default (PAI canonical Pulse is macOS launchd). Verify via `pai-doctor`.
- ElevenLabs SDK requires API key configured in PAI canonical install. No key → TTS fails silently.
- Loopback only — never expose `/notify` publicly. Mobile push happens via Pulse's own routing, not direct from external.

## Cost

- ElevenLabs charge per character synthesized — keep messages concise.
- Pulse caches identical messages briefly — repeat same alert won't re-bill.

## Triggers in Hermes natural language

- "notify me when this is done" → wrap final result in pai-pulse call
- "voice my last commit message" → `git log -1 --pretty=%s` → pai-pulse
- "tell me on my phone X" → pai-pulse → Pulse routes to mobile
- "alert me at 17:00 to check the deploy" → Hermes cron + pai-pulse skill

## Example invocation from skill chain

After `omc ralph` finishes:
```
pai-pulse: {"message": "Ralph completed: 3 tests fixed, 1 file modified."}
```

User hears via mobile within seconds.
