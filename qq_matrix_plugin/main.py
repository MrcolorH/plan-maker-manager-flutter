#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import urllib.error

SERVER_BASE = "http://127.0.0.1:3000"

def is_matrix_owner(qq_id):
    """判断当前发送者是否为 QQMatrix 机器人主人 (Owner)"""
    # 1. 优先读取 QQMatrix 透传的最高权限环境变量
    if os.environ.get("QQMATRIX_IS_MASTER") == "1" or os.environ.get("TGBOT_IS_MASTER") == "1":
        return True

    if not qq_id:
        return False

    # 2. 回退机制：直接读取 ~/.qqmatrix/config.json 或 ~/.tgbot/config.json
    home = os.path.expanduser("~")
    config_paths = [
        os.path.join(home, ".qqmatrix", "config.json"),
        os.path.join(home, ".tgbot", "config.json")
    ]
    for p in config_paths:
        if os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                    master_raw = cfg.get("qqMasterAdminIds", "")
                    master_list = [x.strip() for x in str(master_raw).split(",") if x.strip()]
                    if str(qq_id).strip() in master_list:
                        return True
            except Exception:
                pass

    return False

def handle_invite(qq_id, args):
    if not is_matrix_owner(qq_id):
        print("⛔️ 权限受限：创建和管理知轻云端邀请码仅限机器人所有者（Owner）操作。")
        return

    sub_cmd = args.strip()

    # 1. 查看邀请码列表
    if sub_cmd.lower() in ["list", "列表", "查看", "ls"]:
        url = f"{SERVER_BASE}/internal/invite/list"
        req = urllib.request.Request(url, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                invites = data.get("invites", [])
                if not invites:
                    print("📋 当前暂无未使用的邀请码。\n👉 发送【/邀请码】或【生成邀请码】即可立即生成一个！")
                    return
                lines = [f"📋 当前有效未使用的邀请码 (共 {len(invites)} 个):"]
                for i, item in enumerate(invites, 1):
                    lines.append(f"  {i}. {item.get('code')} ({item.get('created_time', '')})")
                lines.append("\n💡 用户在知轻 App [设置 -> 云端同步] 使用上述任意一个邀请码即可完成注册。")
                print("\n".join(lines))
        except Exception as e:
            print(f"❌ 获取邀请码失败，请确认知轻微服务正常运行: {e}")
        return

    # 2. 生成邀请码 (随机或指定)
    url = f"{SERVER_BASE}/internal/invite/create"
    payload_data = {}
    if sub_cmd:
        payload_data["code"] = sub_cmd

    payload = json.dumps(payload_data).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                code = data.get("code")
                print(f"🎟️【知轻云端邀请码创建成功】\n\n新邀请码：{code}\n\n📱 使用说明：新用户在知轻 App [设置 -> 云端同步 -> 没有账号？使用邀请码注册] 中填入此邀请码即可完成注册。\n(每个邀请码仅可注册一次，注册后自动核销)")
            else:
                print(f"❌ 创建邀请码失败: {data.get('message', '未知错误')}")
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = err_body.get("error", {}).get("message", str(e))
            print(f"❌ 创建邀请码失败: {msg}")
        except Exception:
            print(f"❌ 服务端响应错误: {e.code}")
    except Exception as e:
        print(f"⚠️ 无法连接到本地知轻服务端，请确保微服务已启动: {e}")

def handle_bind(qq_id, args):
    if not args and len(sys.argv) > 1:
        args = sys.argv[1].strip()

    if not args:
        print("💡 请输入 6 位配对码，例如：/bind 839102")
        return

    code = args.split()[0]
    if len(code) != 6 or not code.isdigit():
        print("❌ 配对码必须为 6 位纯数字，请在知轻 App [设置 -> 云端同步] 中查看或重新生成")
        return

    url = f"{SERVER_BASE}/internal/account/qq-bind-confirm"
    payload = json.dumps({"qqId": qq_id, "code": code}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                print(f"🎉 绑定成功！已将当前 QQ ({qq_id}) 绑定至知轻账号【{data.get('username')}】！\n现在估算餐品后发送【导入知轻】即可一键入账。")
            else:
                print(f"❌ 绑定失败: {data.get('message', '未知错误')}")
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = err_body.get("error", {}).get("message", str(e))
            print(f"❌ {msg}")
        except Exception:
            print(f"❌ 服务端响应错误: {e.code}")
    except Exception:
        print("⚠️ 无法连接到本地知轻服务端，请确保知轻微服务已启动 (127.0.0.1:3000)")

def handle_sync(qq_id, args, sender_name):
    # 候选文本提取优先级：
    # 1. 显式引用回复的消息 (QQMATRIX_QUOTED_TEXT)
    # 2. 会话历史中助手的上一条消息 (QQMATRIX_PRECEDING_TEXT)
    # 3. 命令行参数 (args)
    quoted = os.environ.get("QQMATRIX_QUOTED_TEXT", "").strip()
    preceding = os.environ.get("QQMATRIX_PRECEDING_TEXT", "").strip()
    candidate_text = quoted or preceding or args

    if not candidate_text:
        print("💡 请长按引用某条包含餐品热量的消息并回复【导入知轻】，或在刚估算完热量后直接发送【导入知轻】即可同步至云端！")
        return

    url = f"{SERVER_BASE}/internal/hooks/skill-exit"
    payload = json.dumps({
        "event": "skill_exit",
        "skillId": "zhiqing_import_cloud",
        "userId": qq_id,
        "senderName": sender_name,
        "lastUserMessage": "导入知轻",
        "lastAssistantMessage": candidate_text
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                note = data.get("note", "已成功存入知轻待录入信箱")
                print(f"🎉 导入成功！\n{note}\n📱 打开知轻 App 首页点击右上角「云同步」即可一键确认入账。")
            else:
                note = data.get("note", "导入失败")
                print(f"{note}\n👉 请在知轻 App [设置 -> 云端同步] 点击【绑定 QQ 快捷录入】获取 6 位数字码，并在本窗口发送：/bind <绑定码>")
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = err_body.get("error", {}).get("message", str(e))
            print(f"❌ 导入失败: {msg}")
        except Exception:
            print(f"❌ 服务端响应错误: {e.code}")
    except Exception:
        print("⚠️ 无法连接到本地知轻服务端，请确保知轻微服务守护进程正常运行 (127.0.0.1:3000)")

def main():
    qq_id = os.environ.get("QQMATRIX_USER_ID", "").strip()
    cmd = os.environ.get("QQMATRIX_CMD", "").strip().lower()
    args = os.environ.get("QQMATRIX_ARGS", "").strip()
    sender_name = os.environ.get("QQMATRIX_SENDER_NAME", "QQ用户").strip()

    if not cmd and len(sys.argv) > 1:
        first_arg = sys.argv[1].strip()
        if first_arg.startswith("/"):
            cmd = first_arg[1:].lower()
        else:
            cmd = first_arg.lower()

    bind_commands = ["bind", "绑定"]
    sync_commands = ["sync", "导入", "导入知轻", "同步知轻", "记入知轻", "导入云端", "同步到知轻", "导入知青", "同步知青", "记入知青"]
    invite_commands = ["invite", "邀请码", "生成邀请码", "创建邀请码"]

    if cmd in bind_commands:
        handle_bind(qq_id, args)
    elif cmd in invite_commands or any(cmd.startswith(s) for s in invite_commands):
        handle_invite(qq_id, args)
    elif cmd in sync_commands or any(cmd.startswith(s) for s in sync_commands):
        handle_sync(qq_id, args, sender_name)
    else:
        # 默认回退：如果有参数且是纯数字，按 bind 处理，否则按 sync 处理
        if args.isdigit() and len(args) == 6:
            handle_bind(qq_id, args)
        else:
            handle_sync(qq_id, args, sender_name)

if __name__ == "__main__":
    main()
