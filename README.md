# find-skills-cn

A **hardened** version of the `find-skills` agent skill from
[vercel-labs/skills](https://github.com/vercel-labs/skills) — for Windows / Git Bash,
non-English users, and non-interactive runs inside coding agents.

> 中文说明见 [README_CN.md](README_CN.md)。

## Why this exists

The upstream skill tells the agent to run `npx skills find "<query>"`. On a **cold npx cache**,
that first has to download the entire CLI and its dependencies. On a flaky npm registry
connection this produces repeated `ECONNRESET` with 20–57s backoffs — and the CLI **never
starts**. An agent making the call sees nothing come back.

Measured, with the npm debug log as evidence:

```
npx -y skills@latest find "react"      exit=124 (killed at 150s)
stdout: 0 bytes   stderr: 0 bytes
npm log: 150s spent downloading skills@1.7.0 + 6 deps, no line touching the CLI
control: skills.sh/api/search?q=react  → HTTP 200 in 0.87s
```

**So the upstream "empty output" bug has nothing to do with Git Bash, PowerShell, or Chinese.**
Full evidence: [EVIDENCE.md](EVIDENCE.md).

## What's different

| | Upstream | This |
|---|---|---|
| Empty output | unaddressed | pre-flight CLI check → don't use `npx` at runtime |
| Telemetry | **on**; every search query is sent to `add-skill.vercel.sh` | `DISABLE_TELEMETRY=1` on every call |
| Query required | not stated | hard rule — bare `find` drops into an interactive TUI |
| Chinese | *(a popular fork says "unsupported, must translate")* | **measurably wrong** — Chinese works and returns relevant results; the corpus is just 3–4 orders of magnitude smaller, so search **both** |
| Windows | *(that fork wraps everything in PowerShell)* | no mechanism supports that; PowerShell only helps for one narrow case (arg encoding) |
| Local skills | not checked | check `~/.claude/skills/` first — faster, sends nothing |
| Install | `add … -g -y` (skips confirmation) | inspect first, then ask; **don't** use `-y` |
| `remove` | `--all` wipes **any** dir containing a `SKILL.md`, no source check; confirmation auto-skipped inside an agent | never `--all`; remove one by name |
| Same-name collision | `add` does `rm -rf <skills>/<name>` + rewrite → **silently clobbers a hand-written skill** | check for name collisions first |
| "No skills found" | printed for **4 different causes** (non-200 / timeout / exception / genuinely empty) — all exit 0 | don't conclude "doesn't exist"; probe the endpoint |
| Telemetry *off* | *(reads as "then nothing leaves")* | **not enough** — `api.github.com` privacy probe, `skills.sh` search & download are **not** gated by the switch |
| Install destination | *(undocumented two-step)* | real body in `~/.agents/skills/`, `~/.claude/skills/` is a junction |

## Install

```bash
# 1. Install the CLI once (avoids the cold-start root cause)
npm i -g skills

# 2. Drop this skill into your agent's skills dir
#    Claude Code:
cp -r . ~/.claude/skills/find-skills-cn/
```

## Use

```bash
DISABLE_TELEMETRY=1 skills find "数据分析"
DISABLE_TELEMETRY=1 skills find "data analysis"
# or
scripts/find.sh "数据分析"
```

## Scope & honesty

This repo contains **only natural-language instructions** (a `SKILL.md`) plus a bash script.
It does **not** modify, bundle, or redistribute the upstream CLI.

[EVIDENCE.md](EVIDENCE.md) includes a **"what I did not verify"** section — including that the
end-to-end fix was not tested on this machine (installing software was out of scope), so the
"pre-install fixes it" claim is a **mechanism-based inference, not a measured result**.

## License

MIT. Upstream © 2026 Vercel, Inc. — LICENSE text preserved verbatim, modifications appended.
Not affiliated with or endorsed by Vercel, Inc. See [NOTICE.md](NOTICE.md).
