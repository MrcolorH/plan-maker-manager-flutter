#!/bin/zsh
# 知轻本地微服务与 Cloudflare 隧道后台守护进程 (由 QQMatrix 插件生命周期统一调度)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:$HOME/.gemini/bin:$PATH"

SERVER_DIR="/Library/Code-Res/plan-maker-manager-flutter/server"

# 1. 启动本地 Node.js 微服务
node "$SERVER_DIR/src/server.js" &
SERVER_PID=$!

# 2. 启动 Cloudflare 隧道
cloudflared tunnel run zhiqing-tunnel &
TUNNEL_PID=$!

trap "kill $SERVER_PID $TUNNEL_PID 2>/dev/null; exit 0" INT TERM HUP EXIT

wait
