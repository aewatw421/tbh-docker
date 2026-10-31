#!/usr/bin/env bash
# 从 Windows 金盘派生子盘（COW overlay）并启动 VM；VNC 观察桌面。
set -uo pipefail

LOG() { echo "[tbh-kvm] $(date '+%F %T') $*"; }
DIE() { echo "[tbh-kvm][FATAL] $*" >&2; exit 1; }

: "${GOLDEN:=/data/golden/golden.qcow2}"
: "${OVERLAY_DIR:=/data/overlays}"
: "${VM_MEM_MB:=6144}"
: "${VM_CPUS:=4}"
: "${VM_NAME:=tbh}"
: "${VNC_PORT:=5900}"
: "${KEEP_OVERLAY:=1}"     # 1=同一实例名复用子盘（保留系统内改动）；0=每次重建回滚到金盘

command -v qemu-system-x86_64 >/dev/null || DIE "qemu-system-x86_64 缺失"
[ -f "$GOLDEN" ] || DIE "金盘不存在：$GOLDEN（见 kvm/make-golden.md）"

mkdir -p "$OVERLAY_DIR"
INSTANCE="${INSTANCE_NAME:-$(hostname)}"
OVERLAY="$OVERLAY_DIR/${VM_NAME}-${INSTANCE}.qcow2"

if [ ! -f "$OVERLAY" ] || [ "$KEEP_OVERLAY" != "1" ]; then
  rm -f "$OVERLAY"
  LOG "从金盘派生子盘：$OVERLAY"
  qemu-img create -f qcow2 -F qcow2 -b "$GOLDEN" "$OVERLAY" >/dev/null
fi

ACCEL="kvm"; CPU_ARGS="-cpu host"
if [ ! -e /dev/kvm ]; then
  ACCEL="tcg"; CPU_ARGS="-cpu max"
  LOG "警告：无 /dev/kvm，使用 TCG 软件模拟（Windows 极慢，仅用于验证）"
fi

LOG "启动 VM: mem=${VM_MEM_MB}M cpus=${VM_CPUS} accel=${ACCEL} vnc=:${VNC_PORT}"
exec qemu-system-x86_64 \
  -name "$VM_NAME-$INSTANCE" \
  -machine q35,accel="$ACCEL" \
  $CPU_ARGS -smp "$VM_CPUS" -m "$VM_MEM_MB" \
  -drive file="$OVERLAY",if=virtio,format=qcow2,cache=writeback,discard=unmap \
  -device virtio-rng-pci \
  -netdev user,id=net0,hostfwd=tcp::3389-:3389 \
  -device virtio-net-pci,netdev=net0 \
  -vga std \
  -device usb-tablet \
  -display vnc=:"$VNC_PORT",password=off \
  -usb -device usb-kbd \
  -rtc base=localtime \
  -no-reboot
