#!/usr/bin/env python3
import os
import sys
import json
import re
import time
import subprocess
import urllib.request
import urllib.error

SERVER_BASE = "http://127.0.0.1:3000"

def check_service_status():
    """检查本地微服务状态，若未运行则唤醒守护进程"""
    local_ok = False
    try:
        with urllib.request.urlopen("http://127.0.0.1:3000/health", timeout=0.8) as r:
            if r.getcode() == 200:
                local_ok = True
    except Exception:
        local_ok = False

    # 若本地微服务未就绪，唤醒 daemon 守护进程拉起服务
    if not local_ok:
        daemon_sh = os.path.join(os.path.dirname(os.path.abspath(__file__)), "daemon.sh")
        if os.path.exists(daemon_sh):
            try:
                subprocess.Popen(
                    ["/bin/zsh", daemon_sh],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    preexec_fn=os.setpgrp
                )
                for _ in range(8):
                    time.sleep(0.5)
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:3000/health", timeout=0.8) as r:
                            if r.getcode() == 200:
                                local_ok = True
                                break
                    except Exception:
                        pass
            except Exception:
                pass

    return local_ok

# 知轻中国营养学会专业营养师标准结构化转换提示词 (输入框保留完整菜名、做法与全部食材，不限字数，绝不省略)
ZHIQING_AI_PROMPT = """你是中国营养学会专业营养师。请把用户输入的餐食描述及AI助手的长文估算回复，精准转换为标准的纯 JSON 对象，用于录入到“知轻”健康 App 的记录输入框中。

【核心规则】
1. content 字段（用于知轻 App 的记录输入框，不限字数，供用户日后回顾这顿吃了什么、怎么做的）：
   - 必须完整保留：规范菜品名称、具体食材及份量（如：番茄300g、鸡蛋100g、烹调油5g、荞麦面60g）、详细做法步骤（若用户或助手提到了放多少油、加水焖/炒/煮/煎等步骤必须完整保留！）；
   - 坚决剔除：任何 AI 客套寒暄与问候（如“这道菜很健康”、“萌萌这就帮主人整理出来啦”、“👉 请核对以上识别是否有误”等）、中间折算计算说明、以及营养建议废话；
   - 严禁粗暴缩略为“xxxx等几项”！
2. items 数组包含所有独立食材项（含烹调油、面条、肉类、蔬菜、主食等）及该项热量；
3. 输出总热量整数（kcal）、蛋白质（g）、碳水化合物（g）、脂肪（g）；
4. slot 字段：根据用户描述中的餐次时间词（如早/中/晚/下午茶/夜宵）或食物属性（如奶茶/咖啡/小零食/水果等加餐）智能判定为 "breakfast"、"lunch"、"dinner" 或 "snack"。

严格只返回一个标准 JSON 对象，不要输出任何其他文字、解释或 markdown 代码块：
{"name":"规范菜名","slot":"breakfast|lunch|dinner|snack","content":"输入框完整详实描述（含菜名、做法步骤与具体食材清单）","calories":总热量整数kcal,"protein":蛋白质整数g,"carbs":碳水整数g,"fat":脂肪整数g,"items":[{"name":"食物名","portion":"重量或份量","calories":该项热量整数}],"detail":"一句话拆解"}"""

def _resolve_meal_slot(cmd="", args="", ai_slot=None, candidate_text="", user_raw=""):
    """
    按三级优先级判定餐次 slot (breakfast / lunch / dinner / snack):
    1. 第一级（显式指令优先）：检测 cmd 或 args 开头关键词
       含 '早' -> breakfast
       含 '午' 或 '中' -> lunch
       含 '晚' -> dinner
       含 '加餐' 或 '零食' -> snack
    2. 第二级（AI 语义识别）：若一级未指定且 ai_slot 合法，则采用该值
    3. 第三级（本地当前时间兜底）：
       05:00 ~ 10:29 -> breakfast
       10:30 ~ 14:29 -> lunch
       14:30 ~ 16:59 -> snack
       17:00 ~ 20:59 -> dinner
       21:00 ~ 04:59 -> snack
    """
    valid_slots = {"breakfast", "lunch", "dinner", "snack"}

    def _match_keyword(text):
        if not text:
            return None
        t = text.lower().strip()
        # 优先检测加餐/零食，避免与正餐冲突
        if "加餐" in t or "零食" in t:
            return "snack"
        if "早" in t:
            return "breakfast"
        if "午" in t or "中" in t:
            return "lunch"
        if "晚" in t:
            return "dinner"
        return None

    # 第一级：检测 cmd
    slot = _match_keyword(cmd)
    if slot:
        return slot

    # 检测 args 开头关键词 (前 15 字符或第一个分词)
    if args:
        first_word = args.strip().split()[0] if args.strip() else ""
        slot = _match_keyword(first_word)
        if slot:
            return slot
        if len(args.strip()) <= 15:
            slot = _match_keyword(args.strip())
            if slot:
                return slot

    # 第二级：AI 语义识别结果
    if ai_slot and str(ai_slot).lower().strip() in valid_slots:
        return str(ai_slot).lower().strip()

    # 第三级：本地当前系统时间兜底
    now = time.localtime()
    minutes = now.tm_hour * 60 + now.tm_min
    if 300 <= minutes <= 629:      # 05:00 ~ 10:29
        return "breakfast"
    elif 630 <= minutes <= 869:    # 10:30 ~ 14:29
        return "lunch"
    elif 870 <= minutes <= 1019:   # 14:30 ~ 16:59
        return "snack"
    elif 1020 <= minutes <= 1259:  # 17:00 ~ 20:59
        return "dinner"
    else:                          # 21:00 ~ 04:59
        return "snack"

def get_last_user_message(qq_id):
    """从 QQMatrix 运行日志中检索用户最近发送的一条真实餐品做法或食物描述"""
    if not qq_id:
        return ""
    log_path = os.path.expanduser("~/.qqmatrix/logs/app.log")
    if not os.path.exists(log_path):
        return ""
    try:
        with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
        for line in reversed(lines[-200:]):
            m = re.search(r'收到来自 .*?\(' + re.escape(str(qq_id)) + r'\) 的私聊:\s*(.+)', line)
            if m:
                text = m.group(1).strip()
                # 过滤掉指令类、纯确认或引用回复消息
                if text.startswith('/') or text.startswith('[CQ:reply') or text in ['确认', '好的', '退出', '导入知轻', '导入知青', '同步知轻']:
                    continue
                return text
    except Exception:
        pass
    return ""

def build_rich_content_local(assistant_text, user_raw, items):
    """本地高精度构建丰满输入框内容：包含菜品名、做法描述及全部食材明细，剔除 AI 废话"""
    clean_text = assistant_text.strip() if assistant_text else ""
    
    # 1. 提炼菜品名称 (例如：从“这道番茄鸡蛋荞麦焖面的搭配很健康”中提炼)
    meal_name = ""
    m_dish = re.search(r'这(?:道|顿|餐|份)(.+?)(?:的搭配|很|非常|做好了|理出来)', clean_text)
    if m_dish:
        meal_name = m_dish.group(1).replace('：', '').replace(':', '').strip()
    
    sections = []
    if meal_name:
        sections.append(f"【{meal_name}】")
    
    if user_raw:
        sections.append(f"做法与描述：{user_raw.strip()}")
    
    if items:
        item_parts = []
        for it in items:
            name = it.get('name', '')
            portion = it.get('portion', '')
            if portion:
                item_parts.append(f"{name} ({portion})")
            else:
                item_parts.append(name)
        sections.append("食材明细：" + "、".join(item_parts))
    elif not user_raw and not meal_name:
        sections.append("餐品打卡")

    return "\n".join(sections)

def convert_via_ai(text, user_raw=""):
    """在 QQ 侧套用知轻专业提示词，调用本地 AI 引擎进行高精度结构化转换"""
    if not text or len(text.strip()) < 10:
        return None

    user_ctx = f"\n用户原始输入/做菜描述：{user_raw}" if user_raw else ""
    full_prompt = f"{ZHIQING_AI_PROMPT}\n\n待转换的餐品描述与估算回复：{user_ctx}\n{text.strip()}"

    # 1. 优先调用本地 AI 网关 (QQMatrix Gemini Sidecar / OpenAI 兼容接口，响应仅需 3~6 秒)
    api_url = "http://127.0.0.1:8080/v1/chat/completions"
    api_model = "gemini-4-hydrogen"
    config_path = os.path.expanduser("~/.qqmatrix/config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                base = cfg.get("apiBaseUrl", "").rstrip("/")
                if base:
                    api_url = f"{base}/chat/completions"
                api_model = cfg.get("apiModel") or api_model
        except Exception:
            pass

    try:
        req_data = {
            "model": api_model,
            "user": "zhiqing_sync",
            "messages": [{"role": "user", "content": full_prompt}],
            "temperature": 0.2
        }
        req = urllib.request.Request(
            api_url,
            data=json.dumps(req_data).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=25) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            choices = data.get("choices", [])
            if choices:
                out = choices[0].get("message", {}).get("content", "")
                m = re.search(r'\{[\s\S]*\}', out)
                if m:
                    obj = json.loads(m.group(0))
                    if isinstance(obj, dict) and "calories" in obj:
                        return obj
    except Exception:
        pass

    # 2. 回退调用 agy CLI
    agy_path = "/Users/colorh/.local/bin/agy"
    home_dir = os.path.expanduser("~")
    if os.path.exists(agy_path):
        env = os.environ.copy()
        env["HOME"] = home_dir
        try:
            res = subprocess.run(
                [agy_path, "-p", full_prompt, "--dangerously-skip-permissions"],
                env=env,
                capture_output=True,
                text=True,
                timeout=30
            )
            if res.returncode == 0 and res.stdout:
                out = res.stdout.strip()
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
    if os.environ.get("QQMATRIX_IS_MASTER") == "1" or os.environ.get("TGBOT_IS_MASTER") == "1":
        return True

    if not qq_id:
        return False

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

def handle_sync(qq_id, args, sender_name, cmd=""):
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

    # 1. 检索用户最近输入的一条真实菜品与做法描述 (如："两个番茄两个鸡蛋5g油炒...")
    user_raw_desc = get_last_user_message(qq_id)

    # 2. 套用知轻专业提示词交由 AI 完成高精度结构化转换
    ai_result = convert_via_ai(candidate_text, user_raw=user_raw_desc)

    if not ai_result:
        print("❌ AI 结构化解析失败：未能成功将餐品估算长文转换为有效营养数据，已取消本次导入。请检查大模型网关状态后重试。")
        return

    # 3. 智能判定餐次 slot (显式指令 > AI语义 > 当前时间兜底)
    ai_slot = ai_result.get("slot") if ai_result else None
    resolved_slot = _resolve_meal_slot(cmd, args, ai_slot, candidate_text, user_raw_desc)

    # 4. 组装发送给知轻云端服务的负载 (纯由 AI 结构化解析结果与 slot 判定驱动)
    url = f"{SERVER_BASE}/internal/hooks/skill-exit"
    meal_name = ai_result.get("name") or ""
    content_text = ai_result.get("content") or ""
    if meal_name and not content_text.startswith(f"【{meal_name}】"):
        rich_content = f"【{meal_name}】\n{content_text}".strip()
    else:
        rich_content = content_text or meal_name or "餐品打卡"

    payload_dict = {
        "event": "skill_exit",
        "skillId": "zhiqing_import_cloud",
        "userId": qq_id,
        "senderName": sender_name,
        "lastUserMessage": "导入知轻",
        "lastAssistantMessage": candidate_text,
        "slot": resolved_slot,
        "content": rich_content,
        "calories": ai_result.get("calories", 0),
        "protein": ai_result.get("protein", 0),
        "carbs": ai_result.get("carbs", 0),
        "fat": ai_result.get("fat", 0),
        "items": ai_result.get("items", []),
    }
    if ai_result.get("detail"):
        payload_dict["detail"] = ai_result.get("detail")

    payload = json.dumps(payload_dict).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                entry = data.get("entry") or {}
                content_text = entry.get("content") or payload_dict.get("content") or "餐品打卡"
                final_slot = entry.get("slot") or resolved_slot
                cal = entry.get("calories") if entry.get("calories") is not None else payload_dict.get("calories", 0)
                p = entry.get("protein") if entry.get("protein") is not None else payload_dict.get("protein", 0)
                f = entry.get("fat") if entry.get("fat") is not None else payload_dict.get("fat", 0)
                c = entry.get("carbs") if entry.get("carbs") is not None else payload_dict.get("carbs", 0)
                items = entry.get("items") or payload_dict.get("items") or []

                slot_cn_names = {
                    "breakfast": "早餐",
                    "lunch": "午餐",
                    "dinner": "晚餐",
                    "snack": "加餐"
                }
                slot_title = slot_cn_names.get(final_slot, "餐品")
                first_line = content_text.splitlines()[0] if content_text else "餐品打卡"
                lines = [
                    f"🎉 成功导入知轻【{slot_title}】！",
                    f"{first_line}",
                    f"🔥 总热量：{cal} kcal",
                    f"🥩 蛋白质：{p}g | 🧈 脂肪：{f}g | 🍚 碳水：{c}g"
                ]
                if items:
                    lines.append("🥗 归档食材清单：")
                    for it in items:
                        p_str = f" ({it.get('portion')})" if it.get('portion') else ""
                        c_str = f" {it.get('calories')} kcal" if it.get('calories') else ""
                        lines.append(f"  • {it.get('name')}{p_str}{c_str}")

                lines.append("📝 做法与食材明细已完整保留。")
                lines.append("📱 打开手机知轻 App 首页（或下拉刷新），即可自动同步入账✨")
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
    check_service_status()
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
    sync_commands = [
        "sync", "导入", "导入知轻", "同步知轻", "记入知轻", "导入云端", "同步到知轻", "导入知青", "同步知青", "记入知青",
        "导入早餐", "记入早餐", "同步早餐",
        "导入午餐", "记入午餐", "同步午餐", "导入中饭", "记入中饭",
        "导入晚餐", "记入晚餐", "同步晚餐", "导入晚饭", "记入晚饭",
        "导入加餐", "记入加餐", "同步加餐"
    ]
    invite_commands = ["invite", "邀请码", "生成邀请码", "创建邀请码"]

    if cmd in bind_commands:
        handle_bind(qq_id, args)
    elif cmd in invite_commands or any(cmd.startswith(s) for s in invite_commands):
        handle_invite(qq_id, args)
    elif cmd in sync_commands or any(cmd.startswith(s) for s in sync_commands):
        handle_sync(qq_id, args, sender_name, cmd=cmd)
    else:
        if args.isdigit() and len(args) == 6:
            handle_bind(qq_id, args)
        else:
            handle_sync(qq_id, args, sender_name, cmd=cmd)

if __name__ == "__main__":
    main()
