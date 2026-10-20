#!/usr/bin/env bash
# 没有 docker compose 插件时的启动脚本：docker run 起容器
set -euo pipefail

cd "$(dirname "$0")"

[ -f .env ] && set -a && . ./.env && set +a

IMAGE_NAME="${IMAGE_NAME:-debian-claude-code}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-claude-code}"

mkdir -p data/workspace data/ssh data/root-claude data/root-cc-connect data/root-gh

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --restart unless-stopped \
    -t \
    -p "${SSH_PORT:-2222}:22" \
    -p "${CC_MGMT_PORT:-9820}:9820" \
    -p "${CC_BRIDGE_PORT:-9810}:9810" \
    -e "SSH_PASSWORD=${SSH_PASSWORD:-}" \
    -e "DEV_PASSWORD=${DEV_PASSWORD:-}" \
    -e "SSH_AUTHORIZED_KEYS=${SSH_AUTHORIZED_KEYS:-}" \
    -e "CC_CONNECT_ENABLED=${CC_CONNECT_ENABLED:-1}" \
    -e "CC_CONNECT_USER=${CC_CONNECT_USER:-root}" \
    -e "TZ=${TZ:-Asia/Shanghai}" \
    -e "ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-}" \
    -e "ANTHROPIC_AUTH_TOKEN=${ANTHROPIC_AUTH_TOKEN:-}" \
    -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
    -v "$(pwd)/data/workspace:/workspace" \
    -v "$(pwd)/data/ssh:/etc/ssh/keys" \
    -v "$(pwd)/data/root-claude:/root/.claude" \
    -v "$(pwd)/data/root-cc-connect:/root/.cc-connect" \
    -v "$(pwd)/data/root-gh:/root/.config/gh" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

echo "容器已启动：$CONTAINER_NAME"
echo "SSH：ssh root@localhost -p ${SSH_PORT:-2222}"
echo "cc-connect 管理界面：http://localhost:${CC_MGMT_PORT:-9820}"
