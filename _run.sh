#!/usr/bin/env bash
# ShowLocation 启动脚本（Linux / macOS 版，等价于 _run.ps1）
# 用法：./_run.sh（首次可能需要 chmod +x _run.sh）

# 进入脚本所在目录（即项目根目录）
cd "$(dirname "$0")" || exit 1

# 可选：手动指定 Flutter / Android SDK 环境（默认用系统已配置好的，按需取消注释）
# export PATH="$HOME/flutter/bin:$PATH"
# export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
# export ANDROID_HOME="$ANDROID_SDK_ROOT"

KEY_FILE="keys/dart_define.json"
KEY_TEMPLATE="keys/dart_define.example.json"

# 高德 Key 注入文件（不入库）。不存在则自动从模板复制一份，提示你填 Key。
if [ ! -f "$KEY_FILE" ]; then
    if [ -f "$KEY_TEMPLATE" ]; then
        cp "$KEY_TEMPLATE" "$KEY_FILE"
        echo "已自动生成 $KEY_FILE"
        echo "请用编辑器打开它，填入你的高德 Key（AMAP_ANDROID_KEY / AMAP_IOS_KEY / AMAP_WEB_KEY）"
        echo "填好后重新运行本脚本即可。"
    else
        echo "[错误] 未找到模板 $KEY_TEMPLATE"
    fi
    read -r -p "按回车退出"
    exit 1
fi

echo "开始 flutter run (AGP 8.11.1 / Gradle 8.14.3 / Kotlin 2.2.20) ..."
flutter run --dart-define-from-file="$KEY_FILE"
echo "=== flutter run 结束, exit: $? ==="
