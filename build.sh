#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_NAME="鼠标自动小助手"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
BUNDLE_ID="local.mouse-wiggler.helper"

# 关掉正在运行的旧实例，避免旧进程占用签名
/usr/bin/pkill -x MouseWiggler >/dev/null 2>&1 || true

mkdir -p "$MACOS_DIR"

/usr/bin/clang \
  -fobjc-arc \
  -O2 \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  "$SCRIPT_DIR/MouseWiggler.m" \
  -o "$MACOS_DIR/MouseWiggler"

# 生成 Info.plist（每次构建重建，确保一致）
rm -f "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -create xml1 "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleName -string "$APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleDisplayName -string "$APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "MouseWiggler" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string "1.2" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string "1" "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert LSUIElement -bool true "$CONTENTS_DIR/Info.plist"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$CONTENTS_DIR/Info.plist"

# 用 ad-hoc 签名整个 app bundle，并显式指定 identifier
# 这样 TCC 会用 bundle-id 而非 CDHash 作为主键，重新编译不会导致授权失效
/usr/bin/codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  --options runtime \
  "$APP_DIR" 2>/dev/null || \
/usr/bin/codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  "$APP_DIR"

# 清除 Launch Services 缓存，让 macOS 重新识别 app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_DIR" >/dev/null 2>&1 || true

echo "已生成：$APP_DIR"
echo ""
echo "如果反复弹权限提示，请执行一次以下命令重置 TCC 授权，然后重新在设置中授权："
echo "  tccutil reset Accessibility $BUNDLE_ID"
