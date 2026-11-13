#!/bin/zsh
# 知轻本地微服务与 Cloudflare 隧道后台守护进程
# 生命周期与 QQMatrix 插件完全绑定：单例运行，平稳自愈，退出时清理干净
export PATH="$HOME/.local/bin:$HOME/.local/node-v22.11.0-darwin-arm64/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.gemini/bin:$PATH"

SERVER_DIR="/Library/Code-Res/plan-maker-manager-flutter/server"
PID_FILE="/tmp/zhiqing_daemon.pid"
MY_PID=$$

# 1. 单例进程锁保护：严禁多开守护脚本，防止互相踩踏
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        if ps -p "$OLD_PID" -o command= 2>/dev/null | grep -q "daemon.sh"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ℹ️ 已有守护进程在运行 (PID: $OLD_PID)，跳过重复启动。"
            exit 0
        fi
    fi
fi
echo "$MY_PID" > "$PID_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ⚡️ 正在启动知轻微服务与隧道守护 (PID: $MY_PID)..."

# 2. 启动或复用本地 Node.js 微服务 (端口 3000)
if lsof -i :3000 >/dev/null 2>&1 && pgrep -f "server/src/server.js" >/dev/null 2>&1; then
    SERVER_PID=$(pgrep -f "server/src/server.js" | head -n 1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ✅ 本地 Node 微服务已在运行 (PID: $SERVER_PID)"
else
    # 清理残留死锁
    pkill -9 -f "server/src/server.js" 2>/dev/null
    cd "$SERVER_DIR"
    node "$SERVER_DIR/src/server.js" &
    SERVER_PID=$!
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ✅ 本地 Node 微服务已启动 (PID: $SERVER_PID)"
fi

# 3. 启动或复用 Cloudflare 隧道 (api.zhiqing.fun)
if pgrep -f "cloudflared tunnel run zhiqing-tunnel" >/dev/null 2>&1; then
    TUNNEL_PID=$(pgrep -f "cloudflared tunnel run zhiqing-tunnel" | head -n 1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🌐 Cloudflare 隧道已在运行 (PID: $TUNNEL_PID)"
else
    cloudflared tunnel run zhiqing-tunnel &
    TUNNEL_PID=$!
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🌐 Cloudflare 安全隧道已启动 (PID: $TUNNEL_PID)"
fi

# 4. 退出清理：当 QQMatrix 关闭插件或退出时，清理 PID 锁和关联子进程
cleanup() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🛑 收到退出信号，正在安全退出微服务与隧道..."
    rm -f "$PID_FILE" 2>/dev/null
    kill -9 "$SERVER_PID" "$TUNNEL_PID" 2>/dev/null
    pkill -9 -P "$MY_PID" 2>/dev/null
    pkill -9 -f "server/src/server.js" 2>/dev/null
    pkill -9 -f "cloudflared tunnel run zhiqing-tunnel" 2>/dev/null
    exit 0
}
trap cleanup INT TERM HUP EXIT

# 5. 后台平稳健康巡检循环
CHECK_COUNTER=0
CONSECUTIVE_FAILS=0

while true; do
    sleep 5
    CHECK_COUNTER=$((CHECK_COUNTER + 1))

    # [检测 1] 本地 Node 服务存活保障
    if ! kill -0 "$SERVER_PID" 2>/dev/null || ! lsof -i :3000 >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ⚠️ Node 微服务未运行，正在拉起..."
        cd "$SERVER_DIR"
        node "$SERVER_DIR/src/server.js" &
        SERVER_PID=$!
    fi

    # [检测 2] Cloudflare 隧道进程存活保障 (如崩溃则自动重新拉起)
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null || ! pgrep -f "cloudflared tunnel run zhiqing-tunnel" >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] ⚠️ Cloudflare 隧道进程已退出，正在拉起..."
        cloudflared tunnel run zhiqing-tunnel &
        TUNNEL_PID=$!
        sleep 2
    fi

    # [检测 3] 公网隧道高容错探活 (每 30 秒探测一次，给予 8 秒充分超时)
    # cloudflared 具备原生断线重连能力，仅在连续 4 次 (2 分钟) 持续异常且本地正常时才做软重启
    if [ $((CHECK_COUNTER % 6)) -eq 0 ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 8 https://api.zhiqing.fun/health 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ]; then
            CONSECUTIVE_FAILS=0
        else
            CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))
            if [ "$CONSECUTIVE_FAILS" -ge 4 ]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Zhiqing-Daemon] 🚨 公网隧道持续无法访问 (HTTP $HTTP_CODE)，执行软重连..."
                kill -9 "$TUNNEL_PID" 2>/dev/null
                pkill -9 -f "cloudflared tunnel run zhiqing-tunnel" 2>/dev/null
                sleep 2
                cloudflared tunnel run zhiqing-tunnel &
                TUNNEL_PID=$!
                CONSECUTIVE_FAILS=0
            fi
        fi
    fi
done
