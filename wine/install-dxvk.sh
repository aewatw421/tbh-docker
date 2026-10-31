#!/usr/bin/env bash
# 可选：DXVK（D3D11 → Vulkan/lavapipe）。黑屏/渲染异常时设 ENABLE_DXVK=1。
set -euo pipefail

LOG() { echo "[tbh][dxvk] $*"; }

: "${WINEPREFIX:=/data/prefix}"
DXVK_VERSION="${DXVK_VERSION:-2.4}"
S32="$WINEPREFIX/drive_c/windows/syswow64"
S64="$WINEPREFIX/drive_c/windows/system32"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LOG "下载 dxvk-$DXVK_VERSION"
curl -fsSL "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz" \
  -o "$TMP/dxvk.tar.gz"

tar xzf "$TMP/dxvk.tar.gz" -C "$TMP"
SRC="$TMP/dxvk-${DXVK_VERSION}/x64"
SRC32="$TMP/dxvk-${DXVK_VERSION}/x32"

LOG "拷贝 DLL 到 prefix"
for f in "$SRC"/*.dll; do cp -f "$f" "$S64/"; done
for f in "$SRC32"/*.dll; do cp -f "$f" "$S32/"; done

LOG "写入 DLL override"
cat > "$TMP/override.reg" <<'EOF'
REGEDIT4

[HKEY_CURRENT_USER\Software\Wine\DllOverrides]
"d3d9"="native"
"d3d10core"="native"
"d3d11"="native"
"dxgi"="native"
EOF
wine regedit "$TMP/override.reg"

LOG "DXVK $DXVK_VERSION 安装完成（依赖 Mesa lavapipe 软件光栅器）"
