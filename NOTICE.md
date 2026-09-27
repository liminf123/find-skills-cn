# NOTICE — 来源、改动与第三方声明

## 本项目是什么

一个**修改版**的 agent skill，用于发现和安装开放 skills 生态里的技能。
它是上游 [vercel-labs/skills](https://github.com/vercel-labs/skills) 中
`skills/find-skills/SKILL.md` 的衍生作品，针对 **Windows / Git Bash、非英文用户、
以及"在 coding agent 里非交互运行"** 这几种场景做了加固。

**本项目只改 SKILL.md（自然语言指令），不改、不重分发上游的 CLI 代码。**
使用者仍然通过 npm 安装并运行上游发布的 `skills` CLI。

## 上游

| 项 | 值 |
|---|---|
| 仓库 | <https://github.com/vercel-labs/skills> |
| 衍生自 | `skills/find-skills/SKILL.md` |
| 版本 | v1.7.0（npm `skills@1.7.0`，2026-09-17 发布） |
| 许可 | MIT，© 2026 Vercel, Inc. |
| 我们的 LICENSE | 逐字保留上游 MIT 原文，仅在末尾**追加**改动声明。原文一字未改。 |

## 改动清单

每条改动及其**实测依据**见 [EVIDENCE.md](EVIDENCE.md)。

**新增**
- 前置检查：CLI 是否已安装（绕开 npx 冷启动 —— 空输出的真根因）
- 隐私披露：跑 `find` 之前告知用户搜索词会外发到第三方
- 本地优先：先查 `~/.claude/skills/`，命中就不联网
- 安装前"先看内容再装"，并明确**不要用 `-y`** 跳过确认
- 超时 / 离线时的行为说明
- 已知坑清单（每条带 `文件:行号` 出处）

**修正**
- 「中文不支持、必须翻译成英文」→ **实测推翻**。中文搜得到且结果对口
- 「PowerShell 是 Windows 通用修法」→ **无机制支撑**；只对"参数编码被损坏"这一窄场景有意义
- 「推荐前看装机量」→ 补上可操作的方法（含"读它的 SKILL.md"这一步，上游漏了）

**默认值收紧**
- 每次调用强制 `DISABLE_TELEMETRY=1` / `DO_NOT_TRACK=1`
- 必须带 query（避免掉进交互式 TUI）

**没有改**
- 上游 CLI 的任何代码
- 上游的搜索/安装语义

## 第三方

- 上游 CLI 运行时依赖：`tar`、`yaml`（发布版 `package.json`）。
  另有 `@vercel/detect-agent`、`@clack/prompts` 等位于 `devDependencies`，
  通过 `obuild` 打进发布产物 `bin/cli.mjs`。
- 本项目**自身不含任何第三方代码**，只有 Markdown 和一个 bash 脚本。
- 本项目**不包含** `vercel-labs/skills` 的源码副本。

## 与上游的关系

本项目是独立社区作品，**与 Vercel, Inc. 无隶属或背书关系**。
上游项目名、组织名仅用于如实标注来源。

## 商标

"Vercel"、"skills.sh" 等为其各自所有者的商标。本项目仅为指代上游而使用这些名称。
