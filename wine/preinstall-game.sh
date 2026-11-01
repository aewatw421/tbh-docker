#!/usr/bin/env bash
# steamcmd 预装 TBH (appid 3678970)
# 注意：F2P 游戏 depot 也要求账号 license（anonymous 会报 No subscription），
# 因此必须提供 STEAM_USER/STEAM_PASS；Steam Guard 开启的账号 steamcmd 可能要验证码，
# 失败时由 Steam 客户端 steam://install 兜底（entrypoint.ensure_game）。
set -uo pipefail

LOG() { echo "[tbh][preinstall] $*"; }

: "${STEAM_APP_ID:=3678970}"
: "${WINEPREFIX:=/data/prefix}"
: "${GAMES_DIR:=$WINEPREFIX/drive_c/games/tbh}"
STEAM_DIR="${STEAM_DIR:-$WINEPREFIX/drive_c/Program Files (x86)/Steam}"

if [ -z "${STEAM_USER:-}" ]; then
  LOG "无 STEAM_USER：匿名无法下载（No subscription），退出交由客户端安装"
  exit 3
fi

mkdir -p "$GAMES_DIR"

LOG "steamcmd 账号登录拉取（Guard 账号可能需要验证码，失败属正常）"
/opt/steamcmd/steamcmd.sh \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir "$GAMES_DIR" \
  +login "$STEAM_USER" "$STEAM_PASS" \
  +app_update "$STEAM_APP_ID" validate \
  +quit
RC=$?

[ -f "$GAMES_DIR/GameAssembly.dll" ] || { LOG "GameAssembly.dll 不存在，下载未完成 rc=$RC"; exit 1; }
LOG "游戏内容就绪：$(du -sh "$GAMES_DIR" | cut -f1)"

# ---- 注册进 Steam 客户端 ----
mkdir -p "$STEAM_DIR/steamapps"
if [ -f "$GAMES_DIR/steamapps/appmanifest_${STEAM_APP_ID}.acf" ]; then
  cp -f "$GAMES_DIR/steamapps/appmanifest_${STEAM_APP_ID}.acf" "$STEAM_DIR/steamapps/" 2>/dev/null || true
fi

LIBVDF="$STEAM_DIR/config/libraryfolders.vdf"
WIN_PATH='C:\\games\\tbh'
if [ -f "$LIBVDF" ]; then
  if ! grep -q 'games..tbh' "$LIBVDF"; then
    python3 - "$LIBVDF" "$WIN_PATH" <<'PY'
import re, sys
path, win_path = sys.argv[1], sys.argv[2]
s = open(path, encoding='utf-8', errors='replace').read()
m = re.search(r'"paths"\s*\{(.*?)\}', s, re.S)
if not m:
    print('no paths block'); sys.exit(1)
block = m.group(1)
idxs = [int(x) for x in re.findall(r'"(\d+)"\s', block)]
n = (max(idxs) + 1) if idxs else 0
block_new = block.rstrip() + f'\n\t\t\t"{n}"\t\t"{win_path}"\n\t\t'
s = s[:m.start(1)] + block_new + s[m.end(1):]
open(path, 'w', encoding='utf-8').write(s)
print('library registered:', win_path)
PY
  else
    LOG "libraryfolders.vdf 已包含 C:\\games\\tbh"
  fi
else
  LOG "libraryfolders.vdf 不存在（Steam 首次运行后生成），跳过自动注册"
fi

LOG "完成。若 Steam 客户端库中未显示游戏，客户端内手动添加库目录 C:\\games\\tbh 或直接在商店安装。"
