#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/DegenerateAge.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/DegenerateAge" "$app_dir/Contents/MacOS/"
for resource in "$binary_dir"/*.bundle; do
    cp -R "$resource" "$app_dir/Contents/Resources/"
done
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DegenerateAge</string>
<key>CFBundleIdentifier</key><string>com.degenerateage.prototype</string>
<key>CFBundleName</key><string>DegenerateAge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_dir"
echo "应用已生成：$app_dir"
