---
name: find-skills-cn
description: >
  Discover and install agent skills from the open skills ecosystem — hardened for
  Windows/Git-Bash, non-English users, and coding agents. Use when the user asks
  "how do I do X", "find a skill for X", "is there a skill that can...", "有没有能
  做X的技能", "找个skill", or otherwise wants to extend agent capabilities. Replaces
  upstream vercel-labs `find-skills`, which hangs on a cold npx cache, silently
  sends every search query to a third party, and steers the agent into installing
  arbitrary third-party skills with `-g -y`.
license: MIT
---

# Find Skills (CN / Windows-hardened)

帮你从开放 skill 生态里**找到并安装** skill。这是上游 [vercel-labs/skills](https://github.com/vercel-labs/skills)
里 `find-skills` 的加固版，改动都有实测依据，见 [EVIDENCE.md](EVIDENCE.md)。

---

## ⚠️ 先读这一节：安装才是真正的风险，不是搜索

搜索最多是外发一个词；**安装会把第三方代码放进你的 agent 会读的目录**，而那一侧的护栏比你想的薄。

**在跑任何 `skills add` / `skills remove` 之前，必须知道这四件事：**

| 风险 | 事实 | 出处 |
|---|---|---|
| **`remove` 会删你的手写 skill** | 候选集是**扫盘**得来的 —— 任何含 `SKILL.md` 的目录都算，**不校验来源**。`remove -g --all` 会删光。**在 agent 里跑时确认提示被自动跳过。** | `src/remove.ts:116-127` |
| **同名安装会静默覆盖** | `add` 的唯一破坏动作是 `rm -rf <skills>/<name>` 然后重写。**同名的手写 skill 会被无提示整目录覆盖。** | `src/installer.ts` |
| **agent 模式下可能自动同意** | 除了 `-y`，检测到 agent 时确认本身就可能被跳过。所以「我没写 `-y`」**不等于**有确认。 | `src/add.ts:1215-1217` |
| **装进来的是指令文本** | skill 落盘后就是 agent 会当指令读的东西，脚本还会原样落地（含可执行位）。装机量高 ≠ 内容安全。 | 见 EVIDENCE.md |

**因此本 skill 的规则是：**

1. **`remove` 一律不用 `--all`。** 要删就**逐个具名删**，先 `skills list` 看清楚有哪些。
2. **装之前先查有没有同名**（`ls ~/.claude/skills/`）。同名就**停下来问用户**，不要覆盖。
3. **不要用 `-y`**，也不要依赖"agent 模式下应该会问我"。
4. **装之前把 SKILL.md 内容给用户看**。装的是会被当指令执行的东西。

> 如果用户已经有手写 skill（本用户有 `virtuoso-skill`、`verify-fix` 等），
> **优先只读地用搜索，不要装。** 找到的东西让用户自己决定要不要。

---

## ⚠️ 隐私：关掉遥测 ≠ 不外发

上游 `find` 会把**你的搜索词原文**发到第三方（`src/find.ts:345-349`）。
关掉遥测开关是必须的，但**它只管遥测，不管别的**（`src/telemetry.ts:86-88`）：

```bash
export DISABLE_TELEMETRY=1     # 或 DO_NOT_TRACK=1
```

**判定规则**（容易踩反，务必按这个来）：
- 变量**存在且非空** → 关。所以 `=1` ✅、`=0` ✅、`=false` ✅ **都关**（JS 里 `"0"` 是真值）
- **空串 `DISABLE_TELEMETRY=` → 仍然开**（等同于没设）。这是个真陷阱。
- 永远写成 `=1`，别赌语义。

**关掉遥测之后仍然会外发的**（这几条不受开关管，必须让用户知道）：

| 外发内容 | 去哪 | 出处 |
|---|---|---|
| 搜索词 | `skills.sh/api/search?q=` | `src/find.ts:17,89-91` |
| **装了哪个 repo / 哪个 skill** | `skills.sh/api/download/…` | `src/blob.ts:469` |
| **私有性探测**（即使是私有仓库也打） | `api.github.com/repos/{owner}/{repo}` | `src/source-parser.ts:86`、`src/add.ts:1303` |

**所以「关遥测」只是把搜索词从发给两家变成发给一家。**
如果用户不接受，唯一的真办法是**不装、只手动 clone**，或者用下面两个变量指向自建镜像：

```bash
export SKILLS_API_URL=<自建搜索端点>      # src/find.ts:17
export SKILLS_DOWNLOAD_URL=<自建下载端点>  # src/blob.ts:48
```

**另有一条必须警惕：`--metadata <json>` 是无过滤的任意 JSON 外发口**（`src/cli.ts:144`）。
**永远不要用它**，也永远不要往里塞任何项目名/路径/内部标识。

---

## ⚠️ 三条操作硬规则

1. **每次调用都带 `DISABLE_TELEMETRY=1`**（理由见上）。

2. **必须带 query，永远不要裸跑 `find`。**
   不带 query 时它**不会给你结果** —— 非 TTY 下在 `src/find.ts:373` 就返回、
   只打印一段用法提示（实测 323ms 退出 0）；真 TTY 下才会进交互界面（`src/find.ts:380`）。
   两种情况 agent 都拿不到任何结果。

3. **中文和英文各搜一遍，不要只搜一种、也不要翻译。**
   「中文搜不到」是**谣言**（实测 `数据分析` 返回 8 条对口结果）；但中文语料的装机量比英文低 3~4 个数量级。
   详见「非英文查询」一节。

---

## 什么时候用

- 「有没有能做 X 的技能」「找个 skill」「帮我找个能做 X 的东西」
- 「怎么做 X」而 X 是常见任务，很可能别人已经写成 skill 了
- 「你能不能做 X」而 X 是需要专门知识的领域
- 想扩展 agent 能力、找工具/模板/工作流

## 前置检查（**这步是上游空输出的真凶，别跳**）

上游让 agent 跑 `npx skills find`。**npx 缓存是冷的时候**，它得先现下整个 CLI 和依赖；
在抖动的 registry 连接上这一步会反复 `ECONNRESET`、退避 20~57 秒，
**150 秒全花在下载上，CLI 一行都没跑起来** —— 表现就是「空输出」。
（一个流行的 Windows 分支把它归咎于"Git Bash 不能跑 npx"，代码里没有对应机制，见 [EVIDENCE.md](EVIDENCE.md#推翻流行-fork-的根因)。）

**先确认 CLI 已装，别每次现下：**

```bash
skills --version 2>/dev/null || npx --no-install skills --version 2>/dev/null
```

没装的话，按顺序选一个（**装之前先问用户**，这是往他机器上装东西）：

```bash
npm i -g skills          # 全局，最省事
npm i -D skills          # 或项目内
npx -y skills …          # 实在要用 npx，至少加 -y 防冷缓存下 npm 的交互式确认
```

**装好了就用 `skills`，别再用 `npx skills`。**

## 步骤

### 1. 先查本地已有的 skill（**上游完全没有这一步**）

本地命中比联网搜**更快，且不外发任何数据**：

```bash
ls ~/.claude/skills/      # Claude Code（本项目装 skill 的落点，见下面第 7 步）
```

有对口的就直接用，**到此为止，不要联网**。没有才往下走。

### 2. 判断领域和任务

拆成「领域 + 具体动作」。例：「帮我看 PR」→ 领域 `code review`，动作 `pr review`。

### 3. 搜索

```bash
DISABLE_TELEMETRY=1 skills find "<query>"
```

- **多试几组关键词**：`test` / `testing` / `unit test` 是三个不同结果集。
- 可选按作者限定：`--owner vercel-labs`

**跑之前告诉用户一句：这条命令会把搜索词发到 skills.sh。** 他有权知道；
不接受就只走第 1 步的本地路径。

### ⚠️ 搜不到时，先别下结论

**`No skills found for "..."` 这一句话对应四种完全不同的情况**，而**退出码一律是 0**
（`src/find.ts:351-355`）：

1. 服务器返回非 200
2. 请求超时
3. 抛异常
4. **真的没有结果**

**四种都打印同一句、都退 0，从输出无法区分。**

所以：
- **不要**看到「没找到」就告诉用户「生态里没有」——可能只是网络抖了。
- **不要**因为「没找到」就去改关键词或翻译——先怀疑网络。
- 想确认到底哪一类，只能**自己独立探一下**（例如直接看 `https://skills.sh/api/search?q=<词>`
  是否返回 200），再决定是换词还是报网络故障。
- 另外注意 `src/find.ts:92` 的 `fetch` **没有超时**，悬挂时不会报错、只会一直等。

### 4. 非英文查询（中文用户看这里）

**中文能用 —— 但中英文两个池子的体量差 3~4 个数量级，所以两种都要搜。**

实测（2026-09-27，每次两次）：

| 查询 | 命中 | 结果质量 |
|---|---|---|
| `数据分析` | 8 条 | **对口**，最高装机 39,774（`china-stock-analysis` / `tushare` / `tushare-finance`） |
| `电路仿真` | 3 条 | 对口但**装机只有 4 / 2 / 2** —— 基本没人用 |
| `data analysis`（英文） | 8 条 | `microsoft/azure-skills` **602,891**、`anthropics/skills` **173,916** |

**怎么用：**

1. **中文原样搜**（不要翻译）：`DISABLE_TELEMETRY=1 skills find "数据分析"`
   → 拿到中文本土 skill（金融、中文文档、国内工具链这类英文池子里**没有**的东西）
2. **再用英文搜同一需求**：`DISABLE_TELEMETRY=1 skills find "data analysis"`
   → 英文池子深得多
3. **两边都摆给用户**，并**如实说明装机量差距** ——
   别把装机量 2 的和装机量 60 万的并列推荐而不加说明。

**匹配算法在服务端**（`skills.sh/api/search`），客户端只是把 query 原样 URL-encode 发出去
（`src/find.ts:87-116`）。所以「为什么中文能搜到」从本仓库源码里答不了 —— 上面的结论是**实测**得来的。

**为什么 fork 的"必须中译英"是错的**：它以为中文搜不到。实测搜得到、且结果对口。
真正会坏的是**参数编码链路**（Git Bash 下中文参数可能被损坏），不是后端能力。

**编码确实坏了怎么办**：先别翻译，用 PowerShell 传参绕开损坏的那一层：

```bash
powershell -NoProfile -Command "skills find '数据分析'"
```

**只为这一条才值得套 PowerShell。** 把它当成"Windows 通用修法"是错的 ——
多一层 shell、多 0.5~1.5 秒启动、多一层引号转义，对"空输出"这个主症状毫无帮助。

### 5. 推荐前**必须**核实（上游只说了"看装机量"，没给方法）

| 查什么 | 怎么查 | 判据 |
|---|---|---|
| 装机量 | 结果里自带 | ≥1K 可推；<100 要谨慎 |
| 来源可信度 | 看 owner | 官方组织（`vercel-labs` / `anthropics` / `microsoft`）优先 |
| 仓库活跃度 | 看 GitHub star 与最近提交 | <100 star 要存疑 |
| **它到底干什么** | **读它的 SKILL.md** | ← 上游漏掉的关键一步。装机量高 ≠ 适合这个用户 |

> 注：有个流行的 Windows 分支**把上游这两步质量把关删掉了**。别用它的版本。

### 6. 装之前：**先给用户看，拿到明确同意**

上游写的是 `npx skills add <pkg> -g -y` —— **`-y` 直接跳过确认**。
对别人写的、要进你 agent 上下文的代码，这个默认是反的。

**不要用 `-y`**（理由见文首「安装才是真正的风险」）。顺序是：

1. 把 skill 的名字、来源、装机量、**它声明的能力**摆给用户
2. **先看内容**（能读到的话）—— 装的是会被 agent 当指令执行的东西
3. **先查同名**（`ls ~/.claude/skills/`），同名就停下来问
4. 用户明确说要，再装：

```bash
DISABLE_TELEMETRY=1 skills add <owner/repo@skill> -g
```

### 7. 装完告知落点（**比看起来复杂，别只说一半**）

```
~/.agents/skills/<name>/        ← 真身（内容在这里）
~/.claude/skills/<name>/        ← 指向真身的 junction（软链）
```

Claude Code 不是 "universal" agent，所以要两段式。**默认走 symlink 模式**；
只有目标目录收敛成一个时才会退化成真实拷贝（`src/add.ts:856,880-882`）。
**换句话说：删 `~/.claude/skills/X` 删的是壳，真身在 `~/.agents/skills/X`。**

要删就 `skills remove <name>`，**逐个具名删，永远不要 `--all`。**

## 已知坑（都带出处）

| 坑 | 说明 | 出处 |
|---|---|---|
| 搜索词外发 | `find` 把 query 原文发到 `add-skill.vercel.sh` | `src/find.ts:345-349` |
| **关遥测≠不外发** | `api.github.com` 私有性探测、`skills.sh` 搜索与下载**都不受开关管** | `src/source-parser.ts:86`、`src/blob.ts:469` |
| **`--metadata` 是任意外发口** | 无过滤 JSON，永远别用 | `src/cli.ts:144` |
| 关遥测的正确写法 | 存在且非空即关；**空串仍开**；写死 `=1` | `src/telemetry.ts:86-88` |
| 遥测黑洞 | `add-skill.vercel.sh` 部分网络下 20s 超时；退出前 flush 还要等 | `src/cli.ts:419`、`src/telemetry.ts:187-191` |
| npx 冷启动挂起 | 空输出的**真根因** | [EVIDENCE.md](EVIDENCE.md) |
| **"没找到"不可信** | 非200/超时/异常/真0 —— 同一句话、退出码都是 0 | `src/find.ts:351-355` |
| fetch 无超时 | 网络抖动时会一直等 | `src/find.ts:92` |
| 裸跑 `find` 无结果 | 非 TTY 下在 `:373` 返回只打印用法；真 TTY 才进 `@clack/prompts`。**都不是挂住，但都拿不到结果** | `src/find.ts:373,380` |
| agent 检测不可控 | 靠第三方包 `@vercel/detect-agent`；它判 `isAgent`，而 `isAgent` 影响是否自动同意安装 | `src/detect-agent.ts:62`、`src/add.ts:1215-1217` |
| **`remove --all` 会删手写 skill** | 扫盘取候选、不校验来源、agent 内跳过确认 | `src/remove.ts:116-127` |

## 上游原始用法（备查）

- 浏览排行榜：<https://skills.sh/>
- 命令别名：`find|search|f|s`、`add|install|a|i`、`list|ls`
- 相关：`skills update`、`skills remove`、`skills list`、`skills init`

## 致谢与许可

上游 [vercel-labs/skills](https://github.com/vercel-labs/skills)（MIT, © 2026 Vercel, Inc.）。
本文件是其 `find-skills` 的修改版，改动与依据见 [EVIDENCE.md](EVIDENCE.md) 与 [NOTICE.md](NOTICE.md)。
