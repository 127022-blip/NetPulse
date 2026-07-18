#!/bin/bash
# NetPulse 构建并运行脚本

cd "/Users/genglei/我的文件/NetPulse"

# 1. 关闭所有正在运行的 NetPulse（先尝试正常退出，再强制杀死）
echo "[NetPulse] 关闭旧程序..."
osascript -e 'tell application "NetPulse" to quit' 2>/dev/null
sleep 1
pkill -9 -f "NetPulse" 2>/dev/null
sleep 2

# 2. 清理桌面所有旧版本（移到回收站）
for app in ~/Desktop/NetPulse*.app; do
  if [ -e "$app" ]; then
    osascript -e "tell application \"Finder\" to delete POSIX file \"$app\"" 2>/dev/null
  fi
done

# 3. 获取新版本号（先计算，避免构建失败也更新）
NUM=$(cat build_number.txt 2>/dev/null || echo "1")
NEW_NUM=$((NUM + 1))

# 4. 构建
echo "[NetPulse] 构建中..."
xcodebuild -project NetPulse.xcodeproj -scheme NetPulse -configuration Release build 2>&1 | tail -3

# 5. 更新版本号
echo $NEW_NUM > build_number.txt

# 6. 复制到桌面
cp -Rp /Users/genglei/Library/Developer/Xcode/DerivedData/NetPulse-egnjfukadhezeufarenhvecwzbdj/Build/Products/Release/NetPulse.app ~/Desktop/NetPulse-1.4.6-\(${NEW_NUM}\).app

# 7. 签名
codesign --force --sign - ~/Desktop/NetPulse-1.4.6-\(${NEW_NUM}\).app

# 8. 同步
sync

echo "✅ Build $NEW_NUM 完成"

# 9. 启动新程序
sleep 1
open ~/Desktop/NetPulse-1.4.6-\(${NEW_NUM}\).app
