#!/bin/bash
# 知轻云端服务与安全隧道一键启动脚本
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "================================================="
echo "🚀 正在启动知轻本地同步服务 (端口 3000)..."
node src/server.js &
SERVER_PID=$!

echo "🌐 正在启动 Cloudflare 安全隧道 (api.zhiqing.fun)..."
cloudflared tunnel run zhiqing-tunnel &
TUNNEL_PID=$!

trap "kill $SERVER_PID $TUNNEL_PID 2>/dev/null; exit" INT TERM

echo "✅ 服务已就绪！公网地址: https://api.zhiqing.fun"
echo "按 Ctrl+C 可停止运行"
echo "================================================="

wait
