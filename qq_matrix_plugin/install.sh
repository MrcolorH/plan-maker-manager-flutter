#!/bin/bash
# 将本插件一键挂载至 QQMatrix 插件目录
TARGET_DIR="$HOME/.qqmatrix/plugins/zhiqing-sync"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.qqmatrix/plugins"

# 清理旧目录或链接
rm -rf "$TARGET_DIR"

# 建立软链接，直接引用知轻项目中的插件源码 (修改立即生效，零拷贝)
ln -s "$SOURCE_DIR" "$TARGET_DIR"

chmod +x "$SOURCE_DIR/bind.py" "$SOURCE_DIR/daemon.sh"

echo "================================================="
echo "✅ 知轻 QQMatrix 插件已成功挂载至: $TARGET_DIR"
echo "🚀 软链接源目录: $SOURCE_DIR"
echo "💡 现在打开 QQMatrix 客户端，在【🔥 动态热更插件】即可看到并开启！"
echo "================================================="
