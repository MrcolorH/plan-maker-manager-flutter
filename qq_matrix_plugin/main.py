#!/usr/bin/env python3
import os
import sys
import json
import re
import subprocess
import urllib.request
import urllib.error

SERVER_BASE = "http://127.0.0.1:3000"

# 知轻中国营养学会专业营养师标准结构化转换提示词 (与知轻 App 内置 kCalorieSys 严格同源)
ZHIQING_AI_PROMPT = """你是中国营养学会专业营养师。请把用户输入的餐食描述或AI助手的长文估算回复，精准转换为标准的纯 JSON 对象。

【核心规则】
1. 语义理解与抗噪：
   - 彻底剔除任何客套寒暄（如“萌萌看清楚啦”、“👉 请核对以上识别是否有误”）、中间计算折算说明、总计小结及宏量汇总等非食物描述；
   - items 数组中必须包含所有真实食材清单（包括烹饪用油、面条、肉类、蔬菜、主食等），严禁遗漏任何食材；
   - 真实烹饪用油（如家常炒菜5-12g油）必须作为独立食材列入 items（如 {"name":"烹调油","portion":"5g","calories":45}）；
2. 给出整餐规范食物名（概括，如：番茄鸡蛋荞麦焖面）、实际总热量（kcal）、蛋白质（g）、碳水化合物（g）、脂肪（g）；
3. 严格遵循能量守恒：总热量 ≈ 蛋白质*4 + 碳水*4 + 脂肪*9。

严格只返回一个标准 JSON 对象，不要输出任何其他文字、解释或 markdown 代码块：
{"name":"规范食物名","calories":总热量整数kcal,"protein":蛋白质整数g,"carbs":碳水整数g,"fat":脂肪整数g,"items":[{"name":"食物名","portion":"重量或份量","calories":该项热量整数}],"detail":"一句话拆解"}"""

def convert_via_ai(text):
    """在 QQ 侧套用知轻专业提示词，调用本地 AI 引擎进行高精度结构化转换"""
    if not text or len(text.strip()) < 10:
        return None

    agy_path = "/Users/colorh/.local/bin/agy"
    home_dir = os.path.expanduser("~")
    if not os.path.exists(agy_path):
        return None

    full_prompt = f"{ZHIQING_AI_PROMPT}\n\n待转换的餐品与热量描述：\n{text.strip()}"
    env = os.environ.copy()
    env["HOME"] = home_dir

    try:
        res = subprocess.run(
            [agy_path, "-p", full_prompt, "--dangerously-skip-permissions"],
            env=env,
            capture_output=True,
            text=True,
            timeout=25
        )
        if res.returncode == 0 and res.stdout:
            out = res.stdout.strip()
            # 正则提取 JSON
            m = re.search(r'\{[\s\S]*\}', out)
            if m:
                obj = json.loads(m.group(0))
                if isinstance(obj, dict) and "calories" in obj:
                    return obj
    except Exception:
        pass

    return None

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

    # 1. 在 QQ 侧优先套用知轻专业提示词交由本地 AI 完成高精度结构化转换
    ai_result = convert_via_ai(candidate_text)

    # 2. 组装发送给知轻云端服务的负载
    url = f"{SERVER_BASE}/internal/hooks/skill-exit"
    payload_dict = {
        "event": "skill_exit",
        "skillId": "zhiqing_import_cloud",
        "userId": qq_id,
        "senderName": sender_name,
        "lastUserMessage": "导入知轻",
        "lastAssistantMessage": candidate_text
    }

    if ai_result:
        payload_dict["content"] = ai_result.get("name")
        payload_dict["calories"] = ai_result.get("calories")
        payload_dict["protein"] = ai_result.get("protein")
        payload_dict["carbs"] = ai_result.get("carbs")
        payload_dict["fat"] = ai_result.get("fat")
        payload_dict["items"] = ai_result.get("items")
        if ai_result.get("detail"):
            payload_dict["detail"] = ai_result.get("detail")

    payload = json.dumps(payload_dict).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                entry = data.get("entry") or {}
                meal_name = entry.get("content") or payload_dict.get("content") or "餐品打卡"
                cal = entry.get("calories") if entry.get("calories") is not None else payload_dict.get("calories", 0)
                p = entry.get("protein") if entry.get("protein") is not None else payload_dict.get("protein", 0)
                f = entry.get("fat") if entry.get("fat") is not None else payload_dict.get("fat", 0)
                c = entry.get("carbs") if entry.get("carbs") is not None else payload_dict.get("carbs", 0)
                items = entry.get("items") or payload_dict.get("items") or []

                lines = [
                    f"🎉 成功导入知轻！",
                    f"🍽️【{meal_name}】",
                    f"🔥 总热量：{cal} kcal",
                    f"🥩 蛋白质：{p}g | 🧈 脂肪：{f}g | 🍚 碳水：{c}g"
                ]
                if items:
                    lines.append("🥗 食材清单：")
                    for it in items[:6]:
                        p_str = f" ({it.get('portion')})" if it.get('portion') else ""
                        c_str = f" {it.get('calories')} kcal" if it.get('calories') else ""
                        lines.append(f"  • {it.get('name')}{p_str}{c_str}")
                    if len(items) > 6:
                        lines.append(f"  ...等共 {len(items)} 项食材")

                lines.append("\n📱 打开手机知轻 App 即可秒级查看入账（云端已预先解析就绪，无需二次等待）✨")
                print("\n".join(lines))
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
    except Exception as e:
        print(f"⚠️ 无法连接到本地知轻服务端，请确保知轻微服务守护进程正常运行 (127.0.0.1:3000): {e}")

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
