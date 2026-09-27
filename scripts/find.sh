#!/usr/bin/env bash
# 加固版 find —— 预检 CLI、强制关遥测、强制带 query。
#
# 用法:  scripts/find.sh "<query>" [--owner <owner>]
#
# 为什么要这个包装：
#   1. 上游 SKILL.md 让 agent 每次裸跑 `npx skills find`。冷缓存时 npx 要先现下
#      整个 CLI，在抖动网络下会挂到超时 —— 表现为「空输出」。
#      本脚本强制走已安装的 CLI，先把这个根因去掉。
#   2. find 会把搜索词上报到 add-skill.vercel.sh；该端点可能是黑洞（退出前 flush 会拖时间）。
#      这里强制关掉。
#   3. 不带 query 会掉进交互式 TUI（非 TTY 环境下是死胡同）。这里直接拒绝。
set -uo pipefail

export DISABLE_TELEMETRY=1
export DO_NOT_TRACK=1

if [ "$#" -eq 0 ]; then
  cat >&2 <<'EOF'
错误：必须带 query。

不带 query 时上游会进入交互式搜索界面（@clack/prompts），
在 agent 的非 TTY 环境里拿不到结果。

用法:  scripts/find.sh "<query>" [--owner <owner>]
例:    scripts/find.sh "数据分析"
       scripts/find.sh "data analysis"
       scripts/find.sh "react" --owner vercel-labs
EOF
  exit 2
fi

# 优先用已安装的 CLI（避开 npx 下载）
if command -v skills >/dev/null 2>&1; then
  exec skills find "$@"
fi

# 退而求其次：本地 node_modules（不走网络）
if [ -f "./node_modules/skills/bin/cli.mjs" ]; then
  exec node ./node_modules/skills/bin/cli.mjs find "$@"
fi

cat >&2 <<'EOF'
错误：没找到 skills CLI。

直接跑 npx 会在冷缓存下现下整个 CLI，在慢/抖的 registry 连接上会挂到超时
（这就是「空输出」的根因，见 EVIDENCE.md）。请先装一次：

    npm i -g skills        # 全局
    npm i -D skills        # 或项目内

装完再跑本脚本。若你确实要用 npx，至少加 -y，防止冷缓存下 npm 的
交互式确认把进程挂住：

    npx -y skills find "<query>"
EOF
exit 3
