#!/bin/bash
# 知轻云端服务与安全隧道一键启动脚本
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "================================================="
echo "🚀 正在启动知轻本地同步服务 (端口 3000)..."
node src/server.js &
SERVER_PID=$!

if ! pgrep -f "cloudflared.*zhiqing-tunnel" >/dev/null 2>&1; then
  echo "🌐 正在启动 Cloudflare 安全隧道 (api.zhiqing.fun)..."
  cloudflared tunnel run zhiqing-tunnel &
  TUNNEL_PID=$!
else
  echo "🌐 Cloudflare 安全隧道已在后台运行，安全复用。"
fi

trap "kill $SERVER_PID 2>/dev/null; exit" INT TERM

echo "✅ 服务已就绪！公网地址: https://api.zhiqing.fun"
echo "按 Ctrl+C 可停止运行"
echo "================================================="

wait
