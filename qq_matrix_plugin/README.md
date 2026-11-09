# 知轻 · QQMatrix 机器人扩展插件

本插件专为 **知轻 (plan-maker-manager-flutter)** 与 **QQMatrix** 机器人联动设计，独立存放在知轻代码仓库中，**不侵入 QQMatrix 本体代码库**。

---

## 目录结构

```
qq_matrix_plugin/
├── plugin.json       # QQMatrix 动态插件清单 (定义指令、守护进程入口)
├── bind.py          # /bind 独立 Python 执行脚本 (响应 QQ 绑定配对)
├── daemon.sh        # 后台守护进程 (管理 Node 服务与 Cloudflare 隧道)
├── install.sh       # 一键挂载软链接脚本
└── README.md        # 说明文档
```

---

## 核心功能

1. **指令配对**：支持在 QQ 中输入 `/bind <6位配对码>` 或 `绑定 <6位配对码>`，将发送者的 QQ 号与知轻账号双向安全绑定；
2. **生命周期自动托管**：当在 QQMatrix 桌面端开启该插件时，自动通过 `daemon.sh` 在后台启动本机的知轻同步微服务与 Cloudflare 隧道；关闭插件或退出 QQMatrix 时自动停止。

---

## 一键安装与挂载

在终端运行以下脚本即可将本插件软链接至 QQMatrix 的动态插件目录：

```bash
cd /Library/Code-Res/plan-maker-manager-flutter/qq_matrix_plugin
./install.sh
```

挂载后，QQMatrix 即可在 **【🔥 动态热更插件】** 面板中识别到本插件，无需重启软件，热加载毫秒级生效！
