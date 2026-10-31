# syntax=docker/dockerfile:1
# KVM 运行器镜像：容器内起 Windows 金盘虚拟机（游戏 + 助手在 VM 内，与原生 Windows 一致）
# 构建不需要 KVM；运行时需要宿主机透传 /dev/kvm（否则退化为 TCG 软件模拟，极慢）

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-utils socat tini ca-certificates curl procps; \
    rm -rf /var/lib/apt/lists/*

COPY kvm/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV GOLDEN=/data/golden/golden.qcow2 \
    OVERLAY_DIR=/data/overlays \
    VM_MEM_MB=6144 \
    VM_CPUS=4 \
    VM_NAME=tbh \
    VNC_PORT=5900

VOLUME ["/data"]
EXPOSE 5900

STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
