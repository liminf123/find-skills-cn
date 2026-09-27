# 证据：上游 `find-skills` 在 Windows 上「空输出」的真实原因

本文档记录本仓库每一次改动的**实测依据**。所有数字都是实跑出来的，不是推断；
凡是推断的地方都标了「推断」。测不出结论的地方也照实写「未验证」。

**上游**：`vercel-labs/skills` v1.7.0（npm `skills@1.7.0`，2026-09-17 发布，MIT）
**测量环境**：Windows 11 Pro for Workstations / Git Bash（非 WSL）/ Node、npm 走本机默认 registry
**测量时间**：2026-09-27

---

## 一句话

「空输出」和 Git Bash、PowerShell、中文**都没有关系**。
真凶是 **`npx` 冷启动**：带上没有任何缓存时，npx 要先从 npm registry 现下整个 CLI 和它的依赖；
在这台机器的网络下这一步反复 `ECONNRESET`、每次退避 20~57 秒，
**150 秒全部耗在下载上，CLI 一行代码都没跑起来**，agent 侧看到的就是「没有输出」。

---

## 1. 复现（一次，只读）

```
命令     : npx -y skills@latest find "react"
时间      : 2026-09-27T02:26:45Z → 02:29:16Z（被 timeout 150 杀掉）
退出码    : 124      ← 是 timeout 杀的，不是 npm 自己的退出码
STDOUT    : 0 字节
STDERR    : 0 字节
```

**关键**：stdout 和 stderr **都是 0 字节**。所以这**不是**「内容输出到了错误的流」，
是进程根本没产出任何东西。

### npm 自己的 debug 日志（真凶在这里）

`%LOCALAPPDATA%\npm-cache\_logs\2026-09-27T02_26_46_627Z-debug-0.log`：

```
:15   http fetch GET https://registry.npmjs.org/skills
        attempt 1 failed with ECONNRESET
:16   http fetch GET 200 https://registry.npmjs.org/skills            36672ms  attempt #2
:49   ... @isaacs%2ffs-minipass  attempt 1 failed with ECONNRESET
:51   ... @isaacs%2ffs-minipass                                       22076ms  attempt #2
:53   ... minipass                                                    26040ms  attempt #2
:56   ... minizlib                                                    57354ms  attempt #2
:100  ... @isaacs/fs-minipass-4.0.1.tgz  attempt 1 failed with ECONNRESET
:103  ...                                                             38409ms  attempt #2
:105  ... minipass-7.1.3.tgz             attempt 2 failed with ECONNRESET
:106  ... yaml-2.9.1.tgz                 attempt 1 failed with ECONNRESET
```

**150 秒全部花在下载 `skills@1.7.0` + 6 个依赖上。日志里没有一行涉及 `skills` CLI 自身。**

### 对照（curl，只读）

| 目标 | 结果 |
|---|---|
| `registry.npmjs.org/skills` | http=200，4.14 s |
| `registry.npmjs.org/skills/-/skills-1.7.0.tgz` | http=200，137,505 B，1.96 s |
| `skills.sh/api/search?q=react&limit=3` | **http=200，0.87 s，返回真实结果** |
| `add-skill.vercel.sh/t`（上游遥测端点） | **curl rc=28，20 s 超时，0 字节 ← 黑洞** |
| 代理 | 无 `*_PROXY` 环境变量 |

→ **`skills.sh` 本身完全通畅（0.87 s）**。慢的是 **npm registry**，而且是**抖动**：
单次 curl 能通（4.14 s），但 npx 并发拉 7 个包时反复 `ECONNRESET` 并触发长退避。

**注意这个区分很重要**：说「网络不通」是错的（curl 单发是 200）。
准确说法是「**并发下载下稳定性差**」。这也解释了为什么很多人在热缓存下**一次就过** ——
缓存命中就不下载，问题消失。**这条是理解全部混乱的钥匙。**

### 1.1 修复方案的端到端验证（**实测，不是推断**）

在一次性沙箱里做的：CLI 装到临时目录、`HOME`/`USERPROFILE` 指向假 HOME、
`DISABLE_TELEMETRY=1`。**没有碰真实配置，没有出网做写操作。**

```
npm i skills --prefix <sandbox>/pkg --registry=https://registry.npmmirror.com
→ added 8 packages in 2s
```

| 用例 | 耗时 | 退出码 | 结果 |
|---|---|---|---|
| `find "react"`（预装 CLI + 关遥测） | **1858 ms** | 0 | 真结果（`mattpocock/skills@tdd` 970.3K 装机等） |
| `find "数据分析"`（中文，端到端） | **1332 ms** | 0 | 真结果（`wind-alice/alicemarket@wind-find-finance-skill` 39.8K 装机等） |
| `find`（裸跑，无 query） | **323 ms** | 0 | 只打印用法提示，**不挂住** |
| `skills --version` | — | 0 | `1.7.0` |

**对照上游那条路径**：`npx -y skills@latest find "react"` → **150 秒被杀，stdout 0 字节**。

→ **「预装 CLI 即可消除空输出」由机制推断升级为实测结论。**

**另外两条也顺带证实了：**
- `skills.sh/api/search` → **HTTP 200，0.756 s** —— 关遥测后它**照样被访问**（证实第 8.1 节）
- `add-skill.vercel.sh/t` → **超时，8 s 0 字节** —— 证实那个黑洞端点确实存在

**副作用核对（跑了什么就报什么）**：
- 真实 `~/.claude/skills/` **内容不变**（仍是 `delegate-task` / `skill-discovery` / `verify-fix` / `virtuoso-skill` 四个）
- 真实 `~/.agents` **仍不存在**
- 沙箱 HOME **零写入**（没有任何文件落进去）
- **未**执行任何 `add` / `install` / `remove` / `sync`

**顺带修正了本文档自己的一个错误**：我原先写「不带 query 会掉进交互式 TUI、
在非 TTY 环境里是死胡同」——**机制说错了**。实测非 TTY 下它在 `src/find.ts:373`
就返回、只打印用法，**不会挂住**。规则仍然成立（拿不到结果），但理由已按实测改正。

---

## 2. 推翻流行 fork 的根因

有个流传较广的 Windows 兼容分支（`KimYx0207/findskill`），它的主张是：
原版在 Windows 上不能正确执行 `npx skills`，修法是**把命令包进 PowerShell**。

**这条根因不成立。**

1. **代码里没有对应机制。** 上游 `find` 路径是纯 Node：`parseFindOptions` → `searchSkillsAPI` → `console.log`
   （`src/find.ts:326-370`）。没有任何依赖 shell 的地方 —— 没有管道、没有 unix 工具、
   没有 `which`/`cat`/`curl`、没有 bash 专有语法。**换外层 shell 改不到任何一行被执行的代码。**
2. **与实测矛盾。** 实测卡在 npm 下载层（上面那份日志），
   **CLI 根本没启动过**。CLI 没启动，就谈不上「CLI 在 Git Bash 下执行失败」。
3. **它的「验证成功」极可能是缓存混淆**（推断）：第一次跑失败时 npx 已经把包装进了缓存，
   第二次重试时缓存命中、秒过 —— 于是归功于「换了 PowerShell」。
   这个假阳性很容易复现，也很容易被当成真的。

**它唯一沾边的是中文参数编码**（见第 4 节），但它给的解释（「后端只支持英文」）**被实测推翻**。
它把「为编码套 PowerShell」当成了「Windows 通用修法」，这是把一个窄场景推广成了通则 ——
代价是每次调用多一层 shell、多 0.5~1.5 s 启动、多一层引号转义，而**对主症状毫无帮助**。

---

## 3. 上游本来就有非交互保护（所以那不是空输出的原因）

```
src/find.ts:329   const isNonInteractive = !process.stdin.isTTY;
src/find.ts:341   if (query) { ...搜查、打印、return }        ← 给了 query 就完全不碰交互
src/find.ts:373   if (isNonInteractive || (await isRunningInAgent())) { 提示用法; return }
src/find.ts:380   const selected = await runSearchPrompt('', owner);     ← 交互 TUI（@clack/prompts）
```

**给了 query 时走的是第 341 行，纯打印路径，和交互无关。**
交互 TUI 只在**不带 query**时才会碰到。所以「交互式 TTY 导致空输出」对主症状不成立
（这条也曾被当作候选根因，已排除）。

> 但这仍是真坑：**不带 query 裸跑 `find`** 拿不到任何结果。
> **本机实测**：非 TTY（`< /dev/null`）下它在 `:373` 就返回、只打印用法提示，
> **323ms 退出 0，不挂住**；真 TTY 下才会进 `runSearchPrompt`（`:380`）。
> 所以「必须带 query」这条规则成立，但理由要写准：**不是"会卡死"，是"拿不到结果"。**
> （我最初把它写成"在非 TTY 环境下会撞上 TUI"，是错的，已按实测改正。）

**另外**：agent 检测外包给了第三方包 `@vercel/detect-agent`（`src/detect-agent.ts:1,62`）。
检测成功 → 跳过 logo、走非交互默认值；检测失败 → 可能掉进交互路径。
它在 `devDependencies` 里，靠 `obuild` 打进 `bin/cli.mjs` —— 所以发布版看起来只有 `tar`+`yaml` 两个依赖。

---

## 4. 中文搜索实测

每次查询各测两遍（`https://skills.sh/api/search?q=<q>&limit=…`）：

| 查询 | HTTP | 命中 | 结果（节选） |
|---|---|---|---|
| `数据分析` | 200 / 200 | 8 条 | `china-stock-analysis` 12,619 · `tushare` 6,134 · `tushare-finance` 5,165 · 最高 39,774 |
| `数据分析 python` | 200 / 200 | 8 条 | `backtrader` 195 · `csv-data-summarizer` 79 · `akshare-stock` 53 |
| `电路仿真` | 200 / 200 | 3 条 | `power-electronics-dcdc-simulink` **4** · `multisim-debug-circuit` **2** · `multisim-create-experiment` **2** |
| `react` | 200 / 200 | 3 条（limit=3） | — |
| `data analysis`（英文对照） | — | 8 条 | `microsoft/azure-skills` **602,891** · `anthropics/skills` **173,916** |

### 结论（比「能」或「不能」都更准确）

- **中文搜索技术上完全可用**，结果也**对口**（搜「电路仿真」真返回电力电子/电路仿真 skill）。
  → 「中文不支持、必须翻译成英文」是**错的**。
- **但中文语料的装机量低 3~4 个数量级**（个位数 vs 几十万）。
  → 中文池子小是**语料问题**（skill 作者以英文用户为主），不是能力问题。
- **所以正确做法是两种都搜**，把两边结果都摆给用户，并**如实说明装机量差距** ——
  不要把装机量 2 的 skill 和装机量 60 万的并列推荐而不说明。

**未验证的部分**：本次没有在**真实中文损坏**的 Git Bash 环境里复现「参数编码坏掉」。
「Git Bash 下中文参数可能被损坏、可用 PowerShell 绕开」是**基于已知 Windows 编码行为的推断**，
不是本机实测。本机 `skills.sh` 侧的中文查询（UTF-8 percent-encode）是实测通过的。

---

## 5. 隐私：搜索词会外发

```
src/find.ts:345-349
  track({ event: 'find', query, resultCount: String(results.length) });
```

`find` **每次都会把用户的搜索词**上报到 `add-skill.vercel.sh`。

叠加两个事实：

1. **那个端点在本机是黑洞** —— `curl rc=28`，20 s 超时，0 字节。
2. **退出前会 flush 遥测** —— `src/cli.ts:419`：`main().finally(() => flushTelemetry()…)`。

→ 收益是双份的：**保护隐私**＋**少等最多 5 秒**。

**关闭方式**（`src/telemetry.ts:86-88`）：

```js
function isEnabled(): boolean {
  return !process.env.DISABLE_TELEMETRY && !process.env.DO_NOT_TRACK;
}
```

判定是「环境变量**存在且非空**」。所以：
`DISABLE_TELEMETRY=1` ✅ · `DO_NOT_TRACK=1` ✅ ·
**`DISABLE_TELEMETRY=0` 也会关** ✅（JS 里字符串 `"0"` 是真值，`!"0"` 为假 → 不启用遥测。反直觉，但确实如此）·
`DISABLE_TELEMETRY=`（空串，等于未设）❌ 不关。

> 对照一个反面案例：另一个 MCP 项目（Windows-MCP）的同名开关**只有精确的 `false` 才关**，
> `0`/`no`/空值全算开。**两个项目的同名变量语义相反** —— 所以这类开关必须读源码确认，不能凭印象。

---

## 6. 本仓库改了什么（逐条对依据）

| 改动 | 依据 |
|---|---|
| 前置检查 CLI 是否已装，装好就别用 `npx` | 第 1 节：空输出的**真根因**是 npx 冷启动 |
| 冷启动时加 `-y` | 防止 npm 冷缓存下的交互式确认把进程挂住（**推断**，见第 1 节候选 H） |
| 每次调用带 `DISABLE_TELEMETRY=1` | 第 5 节：隐私 + 最多省 5 s |
| 硬规则：必须带 query | 第 3 节：不带 query 会进交互 TUI |
| 硬规则：中英文各搜一遍 | 第 4 节：中文可用但池子小 3~4 个数量级 |
| 纠正「中文必须翻译」 | 第 4 节：实测推翻 |
| 纠正「PowerShell 是 Windows 通用修法」 | 第 2 节：无机制支撑，只对编码这一窄场景有意义 |
| 加「先查本地 `~/.claude/skills/`」 | 上游完全没有这步；本地命中比联网快且不外发数据 |
| 搜前告知用户「搜索词会外发」 | 第 5 节 |
| 装之前不用 `-y`、先看内容再装 | 装的是会被 agent 当指令执行的东西，跳过确认的默认是反的 |
| 加超时/离线说明 | 第 1 节：抖动是本机的常态 |
| 新增「安装才是真正的风险」整节 | 第 7 节：`remove --all` / 同名覆盖 / agent 内跳过确认 |
| `remove` 禁用 `--all`（改为逐个具名） | 第 7.1 节 |
| 装前必须查同名、撞名停下来问 | 第 7.2 节 |
| 不再声称"关掉遥测就保护了隐私" | 第 8.1 节：三条外发不受开关管 |
| 新增 `--metadata` 禁用警告 | 第 8.1 节末 |
| 新增自建镜像变量 `SKILLS_API_URL` / `SKILLS_DOWNLOAD_URL` | 第 8.1 节 |
| 把"搜不到先怀疑编码"改成"先别下结论" | 第 8.2 节：四种情况同一输出、退出码都是 0 |
| 落点改成两段式（`.agents/skills` 真身 + junction） | 第 7.4 节 |
| 提示「打包面比 dependencies 看起来大」 | 第 7.5 节 |

## 7. 安装侧的证据（**风险最高的一侧**）

搜索最多外发一个词；安装会把第三方代码放进 agent 会读的目录。这一侧的护栏比文档给人的印象薄。

### 7.1 `remove --all` 会删掉用户手写的 skill

```
src/remove.ts:116-127
```

候选集是**扫盘**得来的 —— **任何含 `SKILL.md` 的目录**都进候选，**不校验来源**。
`remove -g --all` 会把它们全删掉，包括用户自己手写的。
**且在 agent 环境里跑时，确认提示被自动跳过**（`isRunningInAgent()` 那条路径）。

→ 本仓库规则：**`remove` 永不 `--all`，只逐个具名删。**

### 7.2 同名 `add` 会静默整目录覆盖

`add` 唯一的破坏动作是 `rm -rf <skills>/<name>` 然后重写（`src/installer.ts`）。
覆盖范围恰好是那一个目录 —— 但如果用户**手写的 skill 同名**，
它会在无提示的情况下被整个替换掉。

→ 本仓库规则：**装之前先 `ls ~/.claude/skills/` 查同名，撞名就停下来问用户。**

### 7.3 「我没写 `-y`」不等于有确认

`src/add.ts:1215-1217`：检测到 agent 时，确认本身就可能被自动跳过。
所以依赖"它会问我"是不安全的。

### 7.4 落点是两段式的（比看起来复杂）

```
~/.agents/skills/<name>/        ← 真身
~/.claude/skills/<name>/        ← 指向真身的 junction
```

`src/add.ts:856` 默认 `'symlink'`；只有 `uniqueDirs.size <= 1` 时才退化成真实拷贝
（`src/add.ts:880-882`）。Claude Code 不是 universal agent，
universal + claude-code = 2 个不同目录 ⇒ **默认走 symlink**。

→ 后果：**删 `~/.claude/skills/X` 删的是壳，真身在 `~/.agents/skills/X`。**

> **这条同时裁决了一个两维相左的争议**：那个流行 fork 让人去改 `~/.agents/skills/...`，
> 有一维认为"对 Claude Code 不生效"。按代码，在默认 symlink 模式下**它是生效的**
> —— 但也仅在 symlink 模式下成立。

### 7.5 打包面比 `package.json` 看起来大

`package.json` 的 `dependencies` 只有 `tar` 和 `yaml`，容易得出"攻击面很小"。
**这个推论不成立**：`build.config.mjs:5` 用 obuild 把 `src/cli.ts` 打成单 bundle，
所以 `simple-git`、`@clack/prompts`、`@vercel/detect-agent`、`picocolors` 这些
**devDependencies 实际会被打进 `dist/` 并执行**。仓库专门带 `ThirdPartyNoticeText.txt` 就是为它们。

## 8. 补充纠正（发布前复核推翻的两条我自己的说法）

### 8.1 「关掉遥测就保护了隐私」—— 半错

关掉遥测**只管遥测**（`src/telemetry.ts:86-88` 那条 `isEnabled()` 只管 track/audit）。
以下外发**不受开关管**：

| 外发 | 去哪 | 出处 |
|---|---|---|
| 搜索词 | `skills.sh/api/search?q=` | `src/find.ts:17,89-91` |
| 装了哪个 repo/skill | `skills.sh/api/download/…` | `src/blob.ts:469` |
| 私有性探测（私有仓库也打） | `api.github.com/repos/{owner}/{repo}` | `src/source-parser.ts:86`、`src/add.ts:1303` |

**准确说法**：关遥测把搜索词从"发给两家"变成"发给一家"。仅此而已。
真要减到零，只能用 `SKILLS_API_URL` / `SKILLS_DOWNLOAD_URL` 指自建镜像，或手动 clone。

顺带一条：遥测本身比同类项目干净 —— **不发**主机名、用户名、机器码、持久化 ID、绝对本地路径
（本地安装显式跳过，`src/add.ts:2019-2020`），未设异常回传通道。
但**你装了什么、搜了什么，Vercel 是知道的**（上面那张表）。

### 8.2 「搜不到就先怀疑编码」—— 错

`src/find.ts:351-355`：**非 200 / 超时 / 抛异常 / 真的 0 结果**，
这四种情况**返回同一个 `[]`、打印同一句 `No skills found for "..."`、退出码一律 0**。

**从输出无法区分。** 所以：
- 不能因为"没找到"就断言生态里没有
- 不能因为"没找到"就去改关键词或翻译 —— 可能只是网络抖了
- 想分清只能**独立探一次**服务端（例如直接看 `skills.sh/api/search?q=` 是否 200）
- 另外 `src/find.ts:92` 的 `fetch` **没有超时**，悬挂时不报错、只一直等

### 8.3 遥测里 `agent` 字段的值

`src/telemetry.ts:160-162` 发的是 `detectedAgentName`，来源是
`src/detect-agent.ts:64` 传入的 **`cachedResult.agent.name`（原始名）**。
`'claude-code'` 只是 `agentNameToType`（`src/detect-agent.ts:44`）这张映射表里的**目标值**，
该映射只被 `getAgentType()` 用。

→ 所以 Claude Code 场景下遥测的 `agent` 字段**大概率是 `claude` 而非 `claude-code`**。
（除非 `@vercel/detect-agent` 本身返回后者的名字 —— 那个包**本仓库没有读**，见第 9 节。）

## 9. 没做到的（如实记录）

- **没有**在真实冷缓存下复现第二次：第一次跑完后 npx 缓存里已有包，
  再跑就命中缓存、「问题消失」——这本身就是第 2 节所说的**假阳性来源**。
  要复现需删 `%LOCALAPPDATA%\npm-cache\_npx\5606f1555d02ef53\`。
- ~~**没有**测 `npm i -g skills` 之后 `skills find` 的完整端到端~~
  **→ 已补做，见第 1.1 节**：在沙箱里（临时目录 + 假 HOME）跑通了，
  英文 1858 ms、中文 1332 ms、裸跑 323 ms，全部退出码 0 且给出真结果。
  仍未做的是**全局安装**（`npm i -g`）那条路径 —— 沙箱用的是 `--prefix` 局部安装。
  两者对 `find` 而言差异只在 CLI 是否已在 PATH 上，**不影响「不下载就不会超时」这个机制**。
- **没有**在 Linux/macOS 上测。上述 Windows 结论不保证跨平台。
- 第 2 节关于 fork「验证成功是缓存混淆」的推断**无法直接证实** ——
  该 fork 没有公开它的验证过程。

### 发布前复核新发现的缺口（更重要的几条）

- **`@vercel/detect-agent` 这个包本仓库从未读过。** 但 `src/detect-agent.ts:1` 直接依赖它，
  它判 `isAgent`，而 `isAgent` **决定 `add` 是否自动同意安装**（`src/add.ts:1215-1217`）。
  它还会读一堆环境变量 —— 是隐私面里**唯一没被审计的组件**。
  第 8.3 节关于遥测 `agent` 字段值的结论依赖它，因此**那条是推断**。
- **`dist/` 从未与 `src/` 对账。** npm 包只发 `dist/`，本仓库读的是 `src/`。
  两者是否一致**没有验证过** —— 所有基于 `文件:行号` 的结论严格来说都指向 `src/`，
  不保证等于用户实际执行的那份代码。
- **「装进来的恶意 skill 能做什么」没有人负责评估。** 它落盘后就是 agent 会读的指令文本，
  脚本会带可执行位原样落地。本仓库给了"装前先看内容"的流程，但**没有**做内容扫描或沙箱评估。
- **`remove` / 同名覆盖的破坏面全部是读码推出来的，没有在沙箱里真跑过。**
  （一次性 fake HOME + 本地临时 skill 仓 + 指向 127.0.0.1 的假 `SKILLS_API_URL` 就能验，
  不碰真实配置也不出网 —— 本仓库没做。）
- **未评估与本用户已有 `skill-discovery` / OpenSpace 的触发层冲突**：
  两者 description 都关于"发现技能"，谁被触发是概率性的，没测。
  也**没测**两者是否会互相干扰（比如 `remove` 会不会删掉 OpenSpace 的侧车目录）。
