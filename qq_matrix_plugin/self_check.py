#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
知轻健康云同步助手 (Zhiqing Sync) - 专属自检脚本
支持作为独立自检工具运行，也支持被 QQMatrix 统一自检脚本通过 --json 参数调用。
"""

import os
import sys
import json
import time
import sqlite3
import urllib.request
import urllib.error
import subprocess

PLUGIN_DIR = os.path.dirname(os.path.realpath(__file__))
SERVER_DIR = os.path.normpath(os.path.join(PLUGIN_DIR, "../server"))
DB_PATH = os.path.join(SERVER_DIR, "data/zhiqing.db")
DAEMON_PID_FILE = "/tmp/zhiqing_daemon.pid"

class ZhiqingPluginSelfCheck:
    def __init__(self):
        self.results = []
        self.has_error = False
        self.has_warning = False

    def add_result(self, name, status, detail, duration_ms=None):
        if status == "FAIL":
            self.has_error = True
        elif status == "WARN":
            self.has_warning = True
        item = {
            "name": name,
            "status": status,
            "detail": detail
        }
        if duration_ms is not None:
            item["duration_ms"] = round(duration_ms, 2)
        self.results.append(item)

    def check_manifest(self):
        manifest_path = os.path.join(PLUGIN_DIR, "plugin.json")
        if not os.path.exists(manifest_path):
            self.add_result("插件配置清单 (plugin.json)", "FAIL", f"清单文件不存在: {manifest_path}")
            return None
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            version = data.get("version", "未知")
            name = data.get("name", "未命名")
            commands = data.get("commands", [])
            skills = data.get("skills", [])
            detail = f"[{name} v{version}] 声明 {len(commands)} 个指令, {len(skills)} 个动态技能"
            self.add_result("插件配置清单 (plugin.json)", "PASS", detail)
            return data
        except Exception as e:
            self.add_result("插件配置清单 (plugin.json)", "FAIL", f"解析失败: {str(e)}")
            return None

    def check_scripts(self, manifest):
        if not manifest:
            return
        scripts = [
            ("入口主脚本", manifest.get("entry", "main.py")),
            ("账号绑定脚本", "bind.py"),
            ("守护进程脚本", manifest.get("daemonEntry", "daemon.sh"))
        ]
        all_ok = True
        details = []
        for label, fname in scripts:
            fpath = os.path.join(PLUGIN_DIR, fname)
            if not os.path.exists(fpath):
                details.append(f"{label} ({fname}) 不存在")
                all_ok = False
            elif not os.access(fpath, os.X_OK):
                # 尝试自动赋予执行权限
                try:
                    os.chmod(fpath, 0o755)
                    details.append(f"{fname} (已自动修复执行权限)")
                except Exception:
                    details.append(f"{fname} (缺少执行权限)")
                    all_ok = False
            else:
                details.append(f"{fname} 可执行")

        if all_ok:
            self.add_result("核心脚本完整性与权限", "PASS", "；".join(details))
        else:
            self.add_result("核心脚本完整性与权限", "FAIL", "；".join(details))

    def check_daemon_process(self):
        daemon_pid = None
        # 1. 检查 PID 文件
        if os.path.exists(DAEMON_PID_FILE):
            try:
                with open(DAEMON_PID_FILE, "r") as f:
                    content = f.read().strip()
                    if content.isdigit():
                        pid = int(content)
                        # 检查进程是否存活
                        res = subprocess.run(["kill", "-0", str(pid)], capture_output=True)
                        if res.returncode == 0:
                            daemon_pid = pid
            except Exception:
                pass

        # 2. 若未从 PID 文件找到，通过 pgrep 兜底
        if not daemon_pid:
            try:
                res = subprocess.run(["pgrep", "-f", "daemon.sh"], capture_output=True, text=True)
                pids = [int(p) for p in res.stdout.strip().split() if p.isdigit()]
                if pids:
                    daemon_pid = pids[0]
            except Exception:
                pass

        if daemon_pid:
            self.add_result("后台守护进程 (daemon.sh)", "PASS", f"运行中 (PID: {daemon_pid})")
        else:
            self.add_result("后台守护进程 (daemon.sh)", "WARN", "未检测到活跃守护进程，插件执行时将尝试按需拉起")

    def check_microservice(self):
        t0 = time.time()
        url = "http://127.0.0.1:3000/health"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "QQMatrix-HealthCheck/1.0"})
            with urllib.request.urlopen(req, timeout=1.5) as resp:
                elapsed_ms = (time.time() - t0) * 1000
                code = resp.getcode()
                body = resp.read().decode("utf-8", errors="ignore")
                if code == 200:
                    try:
                        data = json.loads(body)
                        srv = data.get("service", "unknown")
                        self.add_result("本地 Node 微服务 (端口 3000)", "PASS", f"服务正常在线 (service: {srv})", elapsed_ms)
                    except Exception:
                        self.add_result("本地 Node 微服务 (端口 3000)", "PASS", f"响应 200 OK", elapsed_ms)
                else:
                    self.add_result("本地 Node 微服务 (端口 3000)", "FAIL", f"HTTP 状态码异常: {code}", elapsed_ms)
        except urllib.error.URLError as e:
            elapsed_ms = (time.time() - t0) * 1000
            self.add_result("本地 Node 微服务 (端口 3000)", "FAIL", f"无法连接 (http://127.0.0.1:3000/health): {e.reason}", elapsed_ms)
        except Exception as e:
            elapsed_ms = (time.time() - t0) * 1000
            self.add_result("本地 Node 微服务 (端口 3000)", "FAIL", f"请求异常: {str(e)}", elapsed_ms)

    def check_cloudflare_tunnel(self):
        try:
            res = subprocess.run(["pgrep", "-f", "cloudflared tunnel run zhiqing-tunnel"], capture_output=True, text=True)
            pids = [p for p in res.stdout.strip().split() if p.isdigit()]
            if pids:
                self.add_result("Cloudflare 安全穿透隧道", "PASS", f"隧道进程在线 (PID: {', '.join(pids)})")
            else:
                self.add_result("Cloudflare 安全穿透隧道", "WARN", "未检测到活跃隧道进程，外网 Webhook 唤醒可能受限")
        except Exception as e:
            self.add_result("Cloudflare 安全穿透隧道", "WARN", f"检测失败: {str(e)}")

    def check_database(self):
        if not os.path.exists(DB_PATH):
            self.add_result("知轻 SQLite 数据库", "FAIL", f"数据库文件不存在: {DB_PATH}")
            return

        size_kb = os.path.getsize(DB_PATH) / 1024
        try:
            conn = sqlite3.connect(DB_PATH, timeout=2.0)
            cur = conn.cursor()
            cur.execute("PRAGMA integrity_check;")
            integrity = cur.fetchone()[0]
            if integrity.lower() != "ok":
                self.add_result("知轻 SQLite 数据库", "FAIL", f"完整性校验失败: {integrity}")
                conn.close()
                return

            cur.execute("SELECT count(*) FROM user_qq_bindings;")
            bindings_count = cur.fetchone()[0]

            cur.execute("SELECT count(*) FROM pending_entries WHERE is_consumed = 0;")
            pending_count = cur.fetchone()[0]

            conn.close()
            detail = f"完整性良好 ({size_kb:.1f} KB), 已绑定 QQ 数: {bindings_count}, 待录入条数: {pending_count}"
            self.add_result("知轻 SQLite 数据库", "PASS", detail)
        except Exception as e:
            self.add_result("知轻 SQLite 数据库", "FAIL", f"查询异常: {str(e)}")

    def run(self):
        manifest = self.check_manifest()
        self.check_scripts(manifest)
        self.check_daemon_process()
        self.check_microservice()
        self.check_cloudflare_tunnel()
        self.check_database()

        overall_status = "FAIL" if self.has_error else ("WARN" if self.has_warning else "PASS")
        return {
            "plugin_id": "zhiqing_sync",
            "plugin_name": "知轻健康云同步助手",
            "status": overall_status,
            "items": self.results,
            "error_count": sum(1 for x in self.results if x["status"] == "FAIL"),
            "warning_count": sum(1 for x in self.results if x["status"] == "WARN")
        }

def main():
    checker = ZhiqingPluginSelfCheck()
    result = checker.run()

    if "--json" in sys.argv:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        sys.exit(1 if result["status"] == "FAIL" else 0)

    # 命令行彩色输出
    status_icon = "🟢" if result["status"] == "PASS" else ("🟡" if result["status"] == "WARN" else "🔴")
    print("\n" + "=" * 55)
    print(f" {status_icon} 插件自检报告: {result['plugin_name']} ({result['status']})")
    print("=" * 55)

    for item in result["items"]:
        icon = "✅" if item["status"] == "PASS" else ("⚠️ " if item["status"] == "WARN" else "❌")
        duration = f" ({item['duration_ms']}ms)" if "duration_ms" in item else ""
        print(f" {icon} {item['name']}{duration}")
        print(f"    └─ {item['detail']}")

    print("-" * 55)
    print(f" 结论: 失败项 {result['error_count']} | 告警项 {result['warning_count']} | 最终状态: {result['status']}\n")
    sys.exit(1 if result["status"] == "FAIL" else 0)

if __name__ == "__main__":
    main()
