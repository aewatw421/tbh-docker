#!/usr/bin/env bash
# TBH 游戏容器入口：Xvfb/VNC → wine prefix → Steam → 游戏 → TBH助手
set -uo pipefail

LOG() { echo "[tbh] $(date '+%F %T') $*"; }
DIE() { echo "[tbh][FATAL] $*" >&2; exit 1; }

export WINEPREFIX="${WINEPREFIX:-/data/prefix}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES-mscoree,mshtml=}"
export DISPLAY="${DISPLAY:-:99}"
STEAM_APP_ID="${STEAM_APP_ID:-3678970}"
GAMES_DIR="${GAMES_DIR:-$WINEPREFIX/drive_c/games/tbh}"
SCREEN="${SCREEN:-1600x900x24}"
VD_SIZE="${VD_SIZE:-${SCREEN%x*}}"          # 1600x900x24 -> 1600x900
STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
HELPER_DELAY="${HELPER_DELAY:-25}"
AUTO_START_HELPER="${AUTO_START_HELPER:-1}"
USE_VIRTUAL_DESKTOP="${USE_VIRTUAL_DESKTOP:-1}"
VNC_PASSWORD="${VNC_PASSWORD:-}"

mkdir -p /data || DIE "挂载卷 /data 不可写"
touch /data/.rwtest || DIE "挂载卷 /data 不可写"

# ---------- 1. 显示栈 ----------
LOG "启动 Xvfb :99 ($SCREEN) + x11vnc + noVNC"
Xvfb :99 -screen 0 "$SCREEN" -nolisten tcp &
XVFB_PID=$!
sleep 1
if [ -n "$VNC_PASSWORD" ]; then
  x11vnc -display :99 -forever -shared -rfbport 5900 -passwd "$VNC_PASSWORD" \
         -xkb -noxrecord -noxfixes -noxdamage >/var/log/x11vnc.log 2>&1 &
else
  x11vnc -display :99 -forever -shared -rfbport 5900 -nopw \
         -xkb -noxrecord -noxfixes -noxdamage >/var/log/x11vnc.log 2>&1 &
fi
websockify --web /usr/share/novnc 6080 localhost:5900 >/var/log/novnc.log 2>&1 &
xset s off -dpms 2>/dev/null || true
openbox >/var/log/openbox.log 2>&1 &

cleanup() {
  LOG "收到停止信号，收尾中…"
  wineserver -k 2>/dev/null || true
  kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup TERM INT

# ---------- 2. wine prefix ----------
if [ ! -f "$WINEPREFIX/system.reg" ]; then
  LOG "初始化 wine prefix（首次，约 1-2 分钟）"
  wineboot -u >/var/log/wineboot.log 2>&1
  wineserver -w
fi

if [ ! -f /data/.winetricks.done ]; then
  LOG "安装 winetricks 组件：corefonts cjkfonts"
  winetricks -q corefonts cjkfonts >/var/log/winetricks.log 2>&1 || LOG "winetricks 失败（继续，可看日志）"
  touch /data/.winetricks.done
fi

if [ "${ENABLE_DXVK:-0}" = "1" ] && [ ! -f /data/.dxvk.done ]; then
  /usr/local/bin/install-dxvk.sh && touch /data/.dxvk.done || LOG "DXVK 安装失败，继续用 wined3d"
fi

# ---------- 3. Steam 客户端 ----------
if [ ! -f "$STEAM_DIR/steam.exe" ]; then
  LOG "安装 Steam 客户端（静默）"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/SteamSetup.exe -o /tmp/SteamSetup.exe \
    || DIE "下载 SteamSetup.exe 失败"
  wine /tmp/SteamSetup.exe /S >/var/log/steamsetup.log 2>&1
  wineserver -w
  rm -f /tmp/SteamSetup.exe
fi

# ---------- 4. 游戏预装（steamcmd 匿名，免费游戏） ----------
if [ "${PREINSTALL:-1}" = "1" ] && [ ! -f "$GAMES_DIR/GameAssembly.dll" ]; then
  LOG "steamcmd 匿名预装 app $STEAM_APP_ID → C:\\games\\tbh"
  /usr/local/bin/preinstall-game.sh || LOG "预装失败：稍后在 Steam 客户端中手动安装即可"
else
  LOG "游戏已就绪或 PREINSTALL=0，跳过 steamcmd"
fi

# ---------- 5. Steam 登录 ----------
LOG "启动 Steam 客户端"
if [ -n "${STEAM_USER:-}" ]; then
  # shellcheck disable=SC2086
  wine "$STEAM_DIR/steam.exe" -silent -noreactlogin -login "$STEAM_USER" "$STEAM_PASS" ${STEAM_ARGS:-} \
    >/var/log/steam.log 2>&1 &
else
  LOG "未提供 STEAM_USER：请在浏览器 http://<host>:6080/vnc.html 手动登录一次（之后免登录）"
  # shellcheck disable=SC2086
  wine "$STEAM_DIR/steam.exe" -silent ${STEAM_ARGS:-} >/var/log/steam.log 2>&1 &
fi

STEAM_READY=0
for i in $(seq 1 90); do
  if pgrep -f 'steam\.exe' >/dev/null 2>&1; then STEAM_READY=1; break; fi
  sleep 2
done
if [ "$STEAM_READY" = 1 ]; then LOG "Steam 进程已就绪"; else LOG "Steam 未检测到（180s），继续后续步骤"; fi
sleep 15

# ---------- 6. 游戏 ----------
GAME_EXE="$(find "$GAMES_DIR" -maxdepth 3 -iname '*.exe' ! -iname '*crash*' -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)"
if [ -n "$GAME_EXE" ] && [ -f "$GAMES_DIR/GameAssembly.dll" ]; then
  LOG "启动游戏：$(basename "$GAME_EXE")"
  (
    cd "$(dirname "$GAME_EXE")" || exit 1
    if [ "$USE_VIRTUAL_DESKTOP" = "1" ]; then
      # shellcheck disable=SC2086
      wine explorer /desktop=shell,"$VD_SIZE" "$(basename "$GAME_EXE")" >/var/log/game.log 2>&1
    else
      # shellcheck disable=SC2086
      wine "$(basename "$GAME_EXE")" >/var/log/game.log 2>&1
    fi
  ) &
else
  LOG "游戏文件缺失：请在 Steam 客户端（noVNC）中安装 appid=$STEAM_APP_ID 后重启容器"
fi

# ---------- 7. TBHHelper ----------
if [ "$AUTO_START_HELPER" = "1" ]; then
  HELPER_EXE="$(find /opt/tbh -maxdepth 2 -iname '*.exe' -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)"
  if [ -n "$HELPER_EXE" ]; then
    LOG "等待 ${HELPER_DELAY}s 后启动助手：$(basename "$HELPER_EXE")"
    sleep "$HELPER_DELAY"
    wine "$HELPER_EXE" >/var/log/helper.log 2>&1 &
  else
    LOG "镜像内未找到助手 EXE"
  fi
else
  LOG "AUTO_START_HELPER=0：请在 noVNC 中手动打开 TBH助手"
fi

LOG "全部组件已拉起。观察/操作：noVNC http://<host>:6080/vnc.html ；日志 /var/log/*.log"
wait -n
LOG "某个子进程退出，容器进入收尾"
cleanup
