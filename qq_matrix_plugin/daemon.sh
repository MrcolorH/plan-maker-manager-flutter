#!/bin/zsh
# 知轻本地微服务与 Cloudflare 隧道后台守护进程 (由 QQMatrix 插件生命周期统一调度)
export PATH="$HOME/.local/bin:$HOME/.local/node-v22.11.0-darwin-arm64/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.gemini/bin:$PATH"

SERVER_DIR="/Library/Code-Res/plan-maker-manager-flutter/server"

# 1. 启动本地 Node.js 微服务 (自动保活)
(
    while true; do
        node "$SERVER_DIR/src/server.js"
        sleep 2
    done
) &
SERVER_PID=$!

# 2. 启动 Cloudflare 隧道 (自动保活)
(
    while true; do
        cloudflared tunnel run zhiqing-tunnel
        sleep 2
    done
) &
TUNNEL_PID=$!

trap "kill $SERVER_PID $TUNNEL_PID 2>/dev/null; pkill -P $SERVER_PID 2>/dev/null; pkill -P $TUNNEL_PID 2>/dev/null; exit 0" INT TERM HUP EXIT

wait
