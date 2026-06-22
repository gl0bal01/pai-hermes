# pai-hermes

**A bridge layer that makes [Hermes Agent](https://github.com/NousResearch/Hermes-Agent) aware of the Personal AI Infrastructure (PAI) ecosystem.**

`pai-hermes` is a small, composition-only package of **7 skills**, **3 scheduled jobs**, and **2 hardened shell wrappers**. It does not modify Hermes, PAI, or any other project — it only *registers itself* with Hermes so the agent can route to tools that already exist on your machine.

| | |
|---|---|
| **Version** | v0.1.4 (2026-06-22) |
| **License** | MIT |
| **Language** | Markdown skills · Bash · a little Python |
| **Status** | Skills + wrappers wired and tested; cron registered through Hermes |

---

## 1. The problem

A capable PAI workstation typically runs four independent systems that **do not know about each other**:

| System | Provides |
|--------|----------|
| **Hermes Agent** (Nous Research) | The daily multi-model agent — voice, memory, sandboxes, built-in cron, reachable from TUI / Telegram / Discord. |
| **PAI canonical** (Daniel Miessler) | The Pulse notification daemon (`127.0.0.1:31337`), ~45 skills, usage tracking, ElevenLabs voice. |
| **oh-my-claudecode (OMC)** | A Claude Code harness with `ralph` / `team` / `autopilot` / `ultrawork` orchestration. |
| **pai-anywhere** | The VPS install socle — Tailscale, HMAC pairing, gateway, dedicated `pai` user. |

Hermes cannot reach PAI's skills or Pulse, cannot drive OMC, nobody watches upstream repos for changes, and PAI's usage meter is invisible outside a Claude Code session.

## 2. What pai-hermes adds

`pai-hermes` is the **glue layer** that teaches Hermes to:

- **Route to OMC** — run `ralph` / `team` / `autopilot` / `ultrawork` from any Hermes surface.
- **Speak through Pulse** — push text-to-speech notifications to your phone.
- **Watch upstream** — hourly `git fetch` across your PAI repos, impact-score the changes, and file **human-gated** upgrade proposals.
- **Guard your subscription** — read Claude's 5-hour / 7-day usage windows and voice-alert before you hit a limit (and refuse high-cost OMC runs when you're close).
- **Brief you daily** — a once-a-day digest (usage, pending proposals, health) pushed to mobile.
- **Probe ecosystem health** — a `doctor` skill covering Pulse, Tailscale, paths, and cron.

Everything above is **composition only**: no source file of Hermes, PAI, OMC, or pai-anywhere is touched.

---

## 3. The 7 skills

Skills are Markdown files (`skills/<name>/SKILL.md`). Each describes *when* Hermes should act and *what command* to run — Hermes itself decides whether to follow the hint and executes it through its own `terminal` toolset.

| Skill | Purpose | Typical trigger |
|-------|---------|-----------------|
| `omc` | Route to the OMC Claude Code harness | "ralph", "team", "autopilot", "ultrawork" |
| `pai-pulse` | Send a Pulse `/notify` TTS message (via `bin/pai-pulse-send`) | "notify me", "tell me when…" |
| `pai-watch` | Fetch + impact-score upstream repos, file proposals | hourly cron · "check upstream" |
| `pai-doctor` | PAI ecosystem health probes | "doctor", "is everything ok?" |
| `pai-accept` | Pin a proposal's SHA in `paths.env` + write an audit review | **SSH-only**, after `pai-watch` proposes |
| `pai-cost-tracker` | Read 5h/7d usage cache, voice-alert on threshold | hourly cron · "usage" |
| `pai-statusline-banner` | Compose a daily mobile digest | daily 18:00 cron |

## 4. The 3 scheduled jobs (zero AI cost)

These are **pure data aggregation — no model calls**, so they cost nothing to run:

| Job | Schedule | What it does |
|-----|----------|--------------|
| `pai-watch` | hourly | `git fetch` + regex impact score → proposals |
| `pai-cost-tracker` | hourly | read usage cache → voice alert if over threshold |
| `pai-statusline-banner` | daily 18:00 | aggregate the day → push digest |

> **Important:** Hermes cron is **not** YAML-file based. Jobs live in `~/.hermes/cron/jobs.json` and are registered **through Hermes itself**. `install.sh` does *not* create them — see [`cron/README.md`](cron/README.md) for the exact registration prompts.

---

## 5. Architecture

```
        laptop · phone · TUI · Telegram · Discord
                        │
                        ▼
           ┌─────────────────────────────┐
           │ Hermes Agent (Python)       │
           │  multi-model · voice · cron │
           └─────────────────────────────┘
              │            │            │
      skill loader     cron sched   terminal toolset
              │            │            │
              ▼            ▼            ▼
      pai-hermes/skills  jobs.json   external CLIs:
      (7 SKILL.md)       (3 jobs)    omc · Pulse /notify · git · jq
                        │
                        ▼  host side (one VPS)
           ┌─────────────────────────────┐
           │ pai-anywhere socle          │
           │  Tailscale · gateway · pai  │
           └─────────────────────────────┘
              │                        │
         PAI canonical            oh-my-claudecode
       (Pulse 31337, voice)     (Claude Code harness)
```

`pai-hermes` registers its `skills/` directory into Hermes' `external_dirs`; Hermes loads them like any other skill. Full design rationale — composition rules, cost discipline, single-source-of-truth table — is in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## 6. Requirements

| Component | Required? | Check |
|-----------|-----------|-------|
| Hermes Agent | **Yes** | `hermes --version` |
| `jq` | **Yes** (skill bodies, wrappers) | `command -v jq` |
| `flock` | **Yes** (`pai-accept` guard) | `command -v flock` |
| `git`, `curl` | **Yes** | `command -v git curl` |
| Python 3 | **Yes** (config patcher, cost check) | `python3 --version` |
| `ruamel.yaml` | **Yes** — `install.sh` auto-installs it | `python3 -c "import ruamel.yaml"` |
| `bats` | For the test suite | `command -v bats` |
| OMC CLI | For the `omc` skill | `omc --version` |
| PAI canonical | Recommended (Pulse, usage cache) | dir at `~/.claude/PAI/` |
| pai-anywhere | Recommended (VPS deploy) | `/etc/pai-anywhere/install-manifest.jsonl` |

Install the common pieces on Debian/Ubuntu:

```bash
sudo apt install -y bats jq git curl util-linux python3 python3-pip
```

---

## 7. Installation

### Local / single machine

```bash
git clone https://github.com/gl0bal01/pai-hermes ~/pai-hermes
cd ~/pai-hermes
less install.sh        # review before running — never pipe installers blindly
./install.sh
```

`install.sh` is **idempotent** and **additive**. It:

1. Symlinks `skills/` into `~/.hermes/skills/pai-hermes`.
2. Adds that directory to `skills.external_dirs` in `~/.hermes/config.yaml` — **appending, never replacing** your existing entries, using a `ruamel.yaml` round-trip so your comments and formatting survive.
3. Backs the config up first, writes it **atomically**, and rolls back if the result does not parse.
4. Validates skill formatting with `bats`.

It does **not** register cron jobs (those go through Hermes — see step below) and **never** modifies Hermes, PAI, or OMC source.

After install:

```bash
# 1. Register the 3 cron jobs through Hermes — see cron/README.md
# 2. Restart Hermes so it loads the new skills
# 3. (Optional) install the SSH-only accept guard system-wide:
sudo ln -sf ~/pai-hermes/bin/pai-accept-guard /usr/local/bin/pai-accept-guard
```

### VPS / production (with pai-anywhere)

The full hardened walkthrough — install pai-anywhere first, run Hermes as the dedicated `pai` user, download-verify-review-execute each installer — is in **[`docs/INSTALL.md`](docs/INSTALL.md)**.

---

## 8. Security model

`pai-hermes` assumes its agent (Hermes) is reachable from **untrusted remote platforms** (Telegram, Discord, …) and can be prompt-injected. Security is therefore enforced in **shell wrappers**, not in skill prose:

- **`pai-accept` is real-SSH-only.** Pinning a trusted SHA into `/etc/pai/paths.env` is the highest-privilege action, so `bin/pai-accept-guard` authorizes it **only when `sshd` is in the invoking process's ancestry** (verified via `/proc` — the spoofable `SSH_*` environment variables are *ignored*). A remotely-driven Hermes has no `sshd` ancestor and is refused. You still operate from anywhere by opening a **Tailscale SSH** session from your phone. The only non-SSH escape hatch is a **root-owned** `/etc/pai/local-accept.allow` (mode `0600`) that a non-root process cannot forge.
- **Pulse notifications go through `bin/pai-pulse-send`.** It builds the JSON body exclusively with `jq --arg` (an injected `$(…)` message is inert) and refuses any non-loopback Pulse URL.
- **Scheduled jobs are zero-cost and read-only** — they cannot trigger paid model calls.
- **AGPL boundary.** `pai-hermes` is MIT. It writes review markdown *into* the AGPL `pai-collab` repo as a filesystem sink only — it never imports, links, or copies AGPL source. See [`CLAUDE.md`](CLAUDE.md).

The guard must **not** be invoked via `sudo -E` / `sudo --preserve-env`: under `EUID=0` it locks all path-bearing variables to canonical locations to prevent `PAI_PATHS_ENV=/etc/shadow`-style overwrites.

---

## 9. Configuration

**Cost thresholds** (single source of truth: `tools/cost_check.py` `DEFAULT_THRESHOLDS`):

| Window | Warn | Alert (voice) | Block |
|--------|------|---------------|-------|
| 5-hour | 60% | 80% | 95% |
| 7-day | 70% | 85% | 95% |

Override per run, or adjust the job through Hermes:

```bash
python3 tools/cost_check.py --thresholds '{"five_hour_alert":70,"seven_day_alert":80}'
```

**Cron jobs** are edited through Hermes (`"Update cron job pai-cost-tracker …"`) or directly in `~/.hermes/cron/jobs.json`. See [`docs/INSTALL.md`](docs/INSTALL.md) §Configure.

---

## 10. Testing

```bash
bats tests/skill-format.bats      # SKILL.md frontmatter + guard security regressions
bats tests/wrappers.bats          # pai-pulse-send: JSON safety + loopback enforcement
bats tests/install-config.bats    # installer: append-not-replace, comment survival, atomicity
python3 -m pytest tests/          # cost_check.py thresholds + edge cases
```

All suites are self-contained (synthetic fixtures, no live Hermes or VPS needed): **40 bats tests + 32 pytest tests**, `shellcheck`-clean.

---

## 11. Project layout

```
pai-hermes/
├── skills/                 # 7 SKILL.md skill definitions
├── bin/
│   ├── pai-accept-guard    # SSH-only enforcer for paths.env mutation
│   └── pai-pulse-send      # jq-safe, loopback-only Pulse notifier
├── tools/
│   ├── cost_check.py       # usage-cache parser + threshold logic
│   └── patch_hermes_config.py  # atomic, comment-preserving config patcher
├── cron/README.md          # how to register the 3 jobs via Hermes
├── install.sh · uninstall.sh
├── tests/                  # bats + pytest
└── docs/                   # INSTALL.md · ARCHITECTURE.md · HERMES_CONTRACT.md
```

---

## 12. Uninstall

```bash
./uninstall.sh        # removes the skills symlink + the external_dirs entry
# then restart Hermes, and delete cron jobs through Hermes if desired
```

`uninstall.sh` restores `~/.hermes/config.yaml` from its backup and leaves Hermes-managed cron jobs untouched (remove them via Hermes). The source checkout is left in place — delete `~/pai-hermes` manually if you no longer want it.

---

## 13. Background

`pai-hermes` replaces an earlier 540-line Bash router (`pai-projet`) that tried to be a unified PAI entrypoint. Most of that surface turned out to overlap Hermes' native capabilities; `pai-hermes` keeps only the ~30% of genuinely PAI-specific glue. The predecessor is retired.

## License

MIT — see [`LICENSE`](LICENSE). Hermes Agent (Nous Research) and PAI canonical (Daniel Miessler) are independent projects under their own licenses; `pai-collab` is AGPL-3.0 and is touched only as a filesystem sink.
