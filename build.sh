#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_NAME="${IMAGE_NAME:-debian-claude-code}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

if ! docker info >/dev/null 2>&1; then
    echo "无法连接 docker 守护进程。" >&2
    echo "如果是权限问题：注销重登，或执行 newgrp docker 后重新运行本脚本。" >&2
    exit 1
fi

docker build \
    --build-arg "DEBIAN_VERSION=${DEBIAN_VERSION:-trixie-slim}" \
    --build-arg "DEV_UID=${DEV_UID:-$(id -u)}" \
    --build-arg "DEV_GID=${DEV_GID:-$(id -g)}" \
    --build-arg "NODE_VERSION=${NODE_VERSION:-22.23.3}" \
    --build-arg "CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION:-latest}" \
    --build-arg "CC_CONNECT_VERSION=${CC_CONNECT_VERSION:-1.5.0}" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    "$@" \
    .

echo "构建完成：${IMAGE_NAME}:${IMAGE_TAG}"
echo "启动：docker compose up -d"
