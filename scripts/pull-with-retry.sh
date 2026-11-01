#!/usr/bin/env bash
# 抗断拉取：docker pull 的**已完成层会保留在本地**，反复重试即可逐层推进。
# 用法：./scripts/pull-with-retry.sh [image] [retries]
set -uo pipefail

IMG="${1:-ghcr.io/aewatw421/tbh-wine:latest}"
MAX="${2:-10}"

for i in $(seq 1 "$MAX"); do
  echo "=== 第 $i/$MAX 次拉取 $IMG ($(date '+%T')) ==="
  if docker pull "$IMG"; then
    echo "✅ 拉取成功：$IMG"
    docker image inspect "$IMG" --format '  digest: {{index .RepoDigests 0}}\n  size:   {{.Size}}'
    exit 0
  fi
  echo "⚠️ 本次失败（多为 unexpected EOF，网络截断）——已完成的层不会重下，10s 后继续"
  sleep 10
done

cat <<'EOF'
❌ 多次重试仍失败。按顺序试：
  1) 给 dockerd 配代理（对 pull 生效；~/.docker/config.json 的 proxies 只管 build/run）
       sudo mkdir -p /etc/systemd/system/docker.service.d
       sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<'CONF'
       [Service]
       Environment="HTTP_PROXY=http://192.168.1.13:7890"
       Environment="HTTPS_PROXY=http://192.168.1.13:7890"
       Environment="NO_PROXY=localhost,127.0.0.1"
       CONF
       sudo systemctl daemon-reload && sudo systemctl restart docker
  2) 用 skopeo 拉（支持 --retry-times，走 HTTPS_PROXY 环境变量）
       HTTPS_PROXY=http://192.168.1.13:7890 skopeo copy --retry-times 10 \
         docker://ghcr.io/aewatw421/tbh-wine:latest docker-daemon:ghcr.io/aewatw421/tbh-wine:latest
  3) 走 Release 离线分片（wget -c 断点续传，最抗断）
       https://github.com/aewatw421/tbh-docker/releases/tag/image-latest
       for f in tbh-wine.tar.zst.part-*; do wget -c <url>/$f; done
       sha256sum -c SHA256SUMS.txt
       cat tbh-wine.tar.zst.part-* | zstd -d | docker load
EOF
exit 1
