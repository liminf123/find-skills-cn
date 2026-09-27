# find-skills-cn

上游 [vercel-labs/skills](https://github.com/vercel-labs/skills) 里 `find-skills` 的**加固版** ——
针对 **Windows / Git Bash、非英文用户、以及在 coding agent 里非交互运行** 这几种场景。

> English: [README.md](README.md)

## 为什么要做这个

上游让 agent 跑 `npx skills find "<query>"`。**npx 缓存是冷的时候**，
它得先把整个 CLI 和依赖现下一遍。在抖动的 npm registry 连接上，
这一步会反复 `ECONNRESET`、每次退避 20~57 秒 —— **CLI 根本没启动**，
agent 那边看到的就是「没有输出」。

实测，证据是 npm 自己的 debug 日志：

```
npx -y skills@latest find "react"      退出码=124（150 秒被 timeout 杀掉）
stdout: 0 字节    stderr: 0 字节
npm 日志: 150 秒全花在下载 skills@1.7.0 + 6 个依赖，没有一行触及 CLI
对照组:   skills.sh/api/search?q=react → HTTP 200，0.87 秒
```

**所以上游那个「空输出」，跟 Git Bash、PowerShell、中文都没关系。**
完整证据：[EVIDENCE.md](EVIDENCE.md)。

## 改了什么

| | 上游 | 本仓库 |
|---|---|---|
| 空输出 | 没处理 | 前置检查 CLI 是否已装，运行时**不用** `npx` |
| 遥测 | **开着**；每次搜索的**搜索词**都发到 `add-skill.vercel.sh` | 每次调用强制 `DISABLE_TELEMETRY=1` |
| 必须带 query | 没写 | 列为硬规则 —— 裸跑会掉进交互界面 |
| 中文 | *（流行分支说"不支持，必须翻译"）* | **实测推翻**：中文搜得到、结果对口；只是语料小 3~4 个数量级，所以**两种都搜** |
| Windows | *（那个分支把所有命令包进 PowerShell）* | 没有机制支撑这种改法；PowerShell 只对一个窄场景（参数编码）有意义 |
| 本地已有 skill | 不查 | 先查 `~/.claude/skills/` —— 更快，且不外发任何数据 |
| 安装 | `add … -g -y`（跳过确认） | 先看内容，再问用户；**不要**用 `-y` |
| **`remove`** | `--all` 会删掉**任何**含 `SKILL.md` 的目录、不校验来源；**在 agent 里跑时确认被自动跳过** | **永不用 `--all`**，只能逐个具名删 |
| **同名冲突** | `add` 做的是 `rm -rf <skills>/<name>` 再重写 → **静默覆盖同名的手写 skill** | 装之前先查同名 |
| 「没找到」 | 非 200 / 超时 / 异常 / 真 0 结果 —— **四种同一个输出、退出码都是 0** | 别据此断言"不存在"，要独立探端点 |
| 关掉遥测 | *（读起来像"那就不外发了"）* | **不够** —— `api.github.com` 私有性探测、skills.sh 的搜索与下载**都不受开关管** |
| 安装落点 | *（没有文档）* | 真身在 `~/.agents/skills/`，`~/.claude/skills/` 是 junction |

## 安装

```bash
# 1. 装一次 CLI（这一步去掉"空输出"的根因）
npm i -g skills

# 2. 把本 skill 放进你的 agent skills 目录
#    Claude Code:
cp -r . ~/.claude/skills/find-skills-cn/
```

## 用法

```bash
DISABLE_TELEMETRY=1 skills find "数据分析"
DISABLE_TELEMETRY=1 skills find "data analysis"
# 或者用包装脚本
scripts/find.sh "数据分析"
```

## 关于中文（这条最容易被搞错）

实测（每次查询各两遍）：

| 查询 | 命中 | 结果 |
|---|---|---|
| `数据分析` | 8 条 | 对口，最高装机 **39,774**（`china-stock-analysis` / `tushare` / `tushare-finance`） |
| `电路仿真` | 3 条 | 对口，但装机只有 **4 / 2 / 2** |
| `data analysis`（英文） | 8 条 | `microsoft/azure-skills` **602,891**、`anthropics/skills` **173,916** |

**中文能用，但中文池子比英文浅 3~4 个数量级。**

所以：**中英文各搜一遍，两边结果都摆给用户，并如实说明装机量差距。**
不要只搜中文（漏掉大部分成熟 skill），也不要只翻译成英文
（漏掉中文特有的金融/中文文档/国内工具链 skill）——
更不要把装机量 2 的和装机量 60 万的并列推荐而不加说明。

## 范围与诚实声明

本仓库**只有自然语言指令**（一个 `SKILL.md`）加一个 bash 脚本。
**不改动、不打包、不再分发**上游的 CLI 代码；使用者仍通过 npm 安装上游发布的 `skills`。

[EVIDENCE.md](EVIDENCE.md) 里有 **「没做到的」** 一节，其中包括：
**本机没有做端到端的修复验证**（往用户环境装软件超出了当时的授权范围），
所以「预装 CLI 就能解决」是**基于机制的直接推论，不是实测结果**。

## 许可

MIT。上游 © 2026 Vercel, Inc. —— LICENSE 原文逐字保留，改动声明仅**追加**在末尾。
与 Vercel, Inc. 无隶属或背书关系。详见 [NOTICE.md](NOTICE.md)。
