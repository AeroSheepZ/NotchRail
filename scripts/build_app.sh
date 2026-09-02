#!/bin/bash
set -e

VERSION="0.0.5"
BUILD_NUM="5"
APP_NAME="NotchRail"
BUILD_DIR=".build/release"
APP_BUNDLE="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🔨 [NotchRail] 正在编译 Release 版本 (v${VERSION})..."
swift build -c release --disable-sandbox

echo "📦 [NotchRail] 正在打包成独立 macOS App (${APP_BUNDLE})..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 1. 复制可执行文件与资源
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 2. 生成标准的 Info.plist
cat << EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.notchrail.NotchRail</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 NotchRail. All rights reserved.</string>
</dict>
</plist>
EOF

# 3. 稳定代码签名（优先使用本地永久 NotchRail-Dev 证书，保证 TCC 权限不丢失）
echo "✍️ [NotchRail] 正在进行稳定代码签名..."
SIGN_IDENTITY="NotchRail-Dev"

if security find-certificate -c "${SIGN_IDENTITY}" > /dev/null 2>&1; then
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
    echo "   - 已使用永久开发证书 (${SIGN_IDENTITY}) 签名，TCC 授权永久有效！"
else
    # 自动尝试创建本地自签名证书
    echo "   - 未检测到 ${SIGN_IDENTITY} 证书，正在自动创建永久开发证书..."
    openssl req -x509 -newkey rsa:2048 -keyout /tmp/NotchRailDev.key -out /tmp/NotchRailDev.crt -days 3650 -nodes -subj "/CN=NotchRail-Dev/O=NotchRail/C=CN" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,digitalSignature,keyCertSign" -addext "extendedKeyUsage=critical,codeSigning" > /dev/null 2>&1 || true
    openssl pkcs12 -export -out /tmp/NotchRailDev.p12 -inkey /tmp/NotchRailDev.key -in /tmp/NotchRailDev.crt -passout pass:notchrail > /dev/null 2>&1 || true
    security import /tmp/NotchRailDev.p12 -P notchrail -T /usr/bin/codesign > /dev/null 2>&1 || true
    rm -f /tmp/NotchRailDev.key /tmp/NotchRailDev.crt /tmp/NotchRailDev.p12
    
    if security find-certificate -c "${SIGN_IDENTITY}" > /dev/null 2>&1; then
        codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
        echo "   - 证书自动创建成功，已使用 (${SIGN_IDENTITY}) 签名！"
    else
        echo "   - 证书创建受限，回退至临时 Ad-hoc 签名..."
        codesign --force --deep --sign - "${APP_BUNDLE}"
    fi
fi

# 4. 生成 ZIP 压缩包 (保留 macOS 文件属性与权限)
ZIP_FILE="build/${APP_NAME}-v${VERSION}.zip"
echo "🗜️ [NotchRail] 正在生成发布 ZIP 包 (${ZIP_FILE})..."
rm -f "${ZIP_FILE}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_FILE}"

# 5. 生成 DMG 镜像包
DMG_FILE="build/${APP_NAME}-v${VERSION}.dmg"
echo "💿 [NotchRail] 正在生成发布 DMG 镜像 (${DMG_FILE})..."
DMG_ROOT="build/dmg_root"
rm -rf "${DMG_ROOT}" "${DMG_FILE}"
mkdir -p "${DMG_ROOT}"
cp -R "${APP_BUNDLE}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov -format UDZO \
  "${DMG_FILE}" > /dev/null

rm -rf "${DMG_ROOT}"

echo "✅ [NotchRail] 打包与分发包制作完成！"
echo "   - App 路径: ${APP_BUNDLE}"
echo "   - DMG 镜像: ${DMG_FILE}"
echo "   - ZIP 压缩包: ${ZIP_FILE}"
