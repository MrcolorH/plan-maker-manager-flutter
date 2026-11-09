#!/usr/bin/env python3
import os
import sys
import json
import urllib.request
import urllib.error

def main():
    qq_id = os.environ.get("QQMATRIX_USER_ID", "").strip()
    args = os.environ.get("QQMATRIX_ARGS", "").strip()
    if not args and len(sys.argv) > 1:
        args = sys.argv[1].strip()

    if not args:
        print("💡 请输入 6 位配对码，例如：/bind 839102")
        return

    code = args.split()[0]
    if len(code) != 6 or not code.isdigit():
        print("❌ 配对码必须为 6 位纯数字，请在知轻 App 中重新查看或生成")
        return

    url = "http://127.0.0.1:3000/internal/account/qq-bind-confirm"
    payload = json.dumps({"qqId": qq_id, "code": code}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})

    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                print(f"🎉 绑定成功！已将当前 QQ ({qq_id}) 绑定至知轻账号【{data.get('username')}】！")
            else:
                print(f"❌ 绑定失败: {data.get('message', '未知错误')}")
    except urllib.error.HTTPError as e:
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            msg = err_body.get("error", {}).get("message", str(e))
            print(f"❌ {msg}")
        except Exception:
            print(f"❌ 服务端响应错误: {e.code}")
    except Exception as e:
        print("⚠️ 无法连接到本地知轻服务端，请确保知轻微服务已启动 (127.0.0.1:3000)")

if __name__ == "__main__":
    main()
