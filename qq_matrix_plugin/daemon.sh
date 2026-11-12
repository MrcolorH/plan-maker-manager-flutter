#!/bin/zsh
# 知轻本地微服务与 Cloudflare 隧道后台守护进程
# 生命周期与 QQMatrix 插件完全绑定：插件开启时自愈运转，插件关闭时全部干净退出
export PATH="$HOME/.local/bin:$HOME/.local/node-v22.11.0-darwin-arm64/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.gemini/bin:$PATH"

SERVER_DIR="/Library/Code-Res/plan-maker-manager-flutter/server"
MY_PID=$$

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ⚡️ 插件已开启，正在启动知轻微服务与隧道守护 (PID: $MY_PID)..."

# 1. 确保旧残留清理干净，防止端口与隧道冲突
for p in $(pgrep -f "server/src/server.js"); do
    kill -9 "$p" 2>/dev/null
done
for p in $(pgrep -f "cloudflared tunnel run zhiqing-tunnel"); do
    kill -9 "$p" 2>/dev/null
done
sleep 1

# 2. 启动本地 Node.js 微服务 (端口 3000)
cd "$SERVER_DIR"
node "$SERVER_DIR/src/server.js" &
SERVER_PID=$!
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ✅ 本地 Node 微服务已启动 (PID: $SERVER_PID)"

# 3. 启动 Cloudflare 隧道 (api.zhiqing.fun)
cloudflared tunnel run zhiqing-tunnel &
TUNNEL_PID=$!
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🌐 Cloudflare 安全隧道已启动 (PID: $TUNNEL_PID)"

# 4. 退出清理陷阱：当 QQMatrix 关闭插件或退出时，杀掉所有关联子进程
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🛑 收到插件关闭信号，正在彻底退出所有微服务与隧道..."
    kill -9 "$SERVER_PID" "$TUNNEL_PID" 2>/dev/null
    pkill -9 -P "$MY_PID" 2>/dev/null
    pkill -9 -f "server/src/server.js" 2>/dev/null
    pkill -9 -f "cloudflared tunnel run zhiqing-tunnel" 2>/dev/null
    exit 0
}
trap cleanup INT TERM HUP EXIT

# 5. 在前台主进程中执行秒级健康自愈循环 (插件开启期间持续保障)
CHECK_COUNTER=0
CONSECUTIVE_FAILS=0

while true; do
    sleep 3
    CHECK_COUNTER=$((CHECK_COUNTER + 1))

    # [检测 1] 本地 Node 服务存活保障
    if ! kill -0 "$SERVER_PID" 2>/dev/null || ! lsof -i :3000 >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ⚠️ Node 微服务未运行，立即触发秒级自愈拉起..."
        cd "$SERVER_DIR"
        node "$SERVER_DIR/src/server.js" &
        SERVER_PID=$!
    fi

    # [检测 2] Cloudflare 隧道进程存活保障
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null || ! pgrep -f "cloudflared tunnel run zhiqing-tunnel" >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ⚠️ Cloudflare 隧道进程已退出，立即触发秒级自愈拉起..."
        cloudflared tunnel run zhiqing-tunnel &
        TUNNEL_PID=$!
        sleep 2
    fi

    # [检测 3] 公网隧道可用性探活 (每 15 秒探测一次)
    if [ $((CHECK_COUNTER % 5)) -eq 0 ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 4 https://api.zhiqing.fun/health 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            CONSECUTIVE_FAILS=0
        else
            CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
            if [ "$CONSECUTIVE_FAILS" -ge 2 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🚨 公网隧道返回 HTTP $HTTP_CODE，触发重启自愈..."
                kill -9 "$TUNNEL_PID" 2>/dev/null
                pkill -9 -f "cloudflared tunnel run zhiqing-tunnel" 2>/dev/null
                sleep 1
                cloudflared tunnel run zhiqing-tunnel &
                TUNNEL_PID=$!
                CONSECUTIVE_FAILS=0
                sleep 3
            fi
        fi
    fi
done
