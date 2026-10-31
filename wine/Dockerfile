# syntax=docker/dockerfile:1
# TBH: Task Bar Hero + TBHHelper — Wine container image
# 构建产物约 2.5GB；游戏本体在首次运行时由 steamcmd 匿名预装到 /data 持久卷。

FROM ubuntu:24.04

ARG WINE_BRANCH=staging
ARG TBH_RELEASE=v1.4.2
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    WINEPREFIX=/data/prefix WINEARCH=win64 WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree,mshtml=" \
    DISPLAY=:99 \
    STEAM_APP_ID=3678970 \
    GAMES_DIR=/data/prefix/drive_c/games/tbh \
    SCREEN=1600x900x24

# ---- 基础工具 + 显示栈 + Mesa 软渲染（llvmpipe / lavapipe） ----
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg2 unzip cabextract xz-utils bzip2 \
      xvfb x11vnc novnc websockify xdotool wmctrl x11-xserver-utils openbox \
      libgl1 libglx-mesa0 libegl1 mesa-vulkan-drivers mesa-utils \
      locales python3-minimal procps tini winbind winetricks \
      fonts-wqy-microhei fonts-noto-cjk; \
    sed -i 's/^# *\(zh_CN.UTF-8\|en_US.UTF-8\)/\1/' /etc/locale.gen; \
    locale-gen; \
    rm -rf /var/lib/apt/lists/*

# ---- WineHQ staging ----
RUN set -eux; \
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key -o /tmp/winehq.asc; \
    gpg --dearmor -o /usr/share/keyrings/winehq.gpg /tmp/winehq.asc; \
    echo "deb [signed-by=/usr/share/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/ubuntu noble main" \
      > /etc/apt/sources.list.d/winehq.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "winehq-${WINE_BRANCH}"; \
    rm -rf /var/lib/apt/lists/*; \
    wine --version

# ---- steamcmd（Linux 版，仅用于匿名预装 Windows 游戏内容） ----
RUN set -eux; \
    mkdir -p /opt/steamcmd; \
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar xz -C /opt/steamcmd; \
    chmod +x /opt/steamcmd/steamcmd.sh

# ---- TBHHelper 直连版 ----
COPY wine/unpack-helper.py /usr/local/bin/unpack-helper.py
COPY wine/entrypoint.sh wine/preinstall-game.sh wine/install-dxvk.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/preinstall-game.sh /usr/local/bin/install-dxvk.sh

ADD https://github.com/buguniaoOVO/TBHHelper/releases/download/${TBH_RELEASE}/TBHHelper-${TBH_RELEASE}.zip /tmp/tbh.zip
RUN set -eux; \
    python3 /usr/local/bin/unpack-helper.py /tmp/tbh.zip /opt/tbh; \
    rm -f /tmp/tbh.zip; \
    find /opt/tbh -maxdepth 2 -iname '*.exe' -printf '%f %s\n'

# ---- noVNC 入口 ----
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

EXPOSE 5900 6080
VOLUME ["/data"]
WORKDIR /data

HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=2 \
  CMD pgrep -f Xvfb >/dev/null || exit 1

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["run"]
