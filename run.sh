#!/usr/bin/env bash
# 没有 docker compose 插件时的启动脚本：docker run 起容器
set -euo pipefail

cd "$(dirname "$0")"

[ -f .env ] && set -a && . ./.env && set +a

IMAGE_NAME="${IMAGE_NAME:-debian-pi-agent}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-pi-agent}"
DATA_DIR="${DATA_DIR:-./data}"

mkdir -p "$DATA_DIR"/workspace "$DATA_DIR"/ssh "$DATA_DIR"/pi "$DATA_DIR"/gh

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --restart unless-stopped \
    -t \
    -p "${SSH_PORT:-2222}:22" \
    -e "SSH_PASSWORD=${SSH_PASSWORD:-}" \
    -e "DEV_PASSWORD=${DEV_PASSWORD:-}" \
    -e "SSH_AUTHORIZED_KEYS=${SSH_AUTHORIZED_KEYS:-}" \
    -e "PI_WORKDIR=${PI_WORKDIR:-/workspace}" \
    -e "FEISHU_ENABLED=${FEISHU_ENABLED:-auto}" \
    -e "FEISHU_APP_ID=${FEISHU_APP_ID:-}" \
    -e "FEISHU_APP_SECRET=${FEISHU_APP_SECRET:-}" \
    -e "FEISHU_BOT_NAME=${FEISHU_BOT_NAME:-Pi Agent}" \
    -e "FEISHU_CONFIG=${FEISHU_CONFIG:-}" \
    -e "FEISHU_GROUP_SCOPE=${FEISHU_GROUP_SCOPE:-shared-chat}" \
    -e "FEISHU_REQUIRE_MENTION=${FEISHU_REQUIRE_MENTION:-1}" \
    -e "FEISHU_DM_ENABLED=${FEISHU_DM_ENABLED:-1}" \
    -e "FEISHU_GROUP_ENABLED=${FEISHU_GROUP_ENABLED:-1}" \
    -e "FEISHU_ALLOW_USERS=${FEISHU_ALLOW_USERS:-}" \
    -e "FEISHU_ALLOW_CHATS=${FEISHU_ALLOW_CHATS:-}" \
    -e "FEISHU_RENDERING_MODE=${FEISHU_RENDERING_MODE:-stream-card}" \
    -e "FEISHU_LOG_LEVEL=${FEISHU_LOG_LEVEL:-info}" \
    -e "FEISHU_DEBUG_EVENTS=${FEISHU_DEBUG_EVENTS:-0}" \
    -e "FEISHU_MAX_UPLOAD_MB=${FEISHU_MAX_UPLOAD_MB:-20}" \
    -e "TZ=${TZ:-Asia/Shanghai}" \
    -e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}" \
    -e "OPENAI_API_KEY=${OPENAI_API_KEY:-}" \
    -e "GEMINI_API_KEY=${GEMINI_API_KEY:-}" \
    -e "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY:-}" \
    -e "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}" \
    -v "$(pwd)/${DATA_DIR#./}/workspace:/workspace" \
    -v "$(pwd)/${DATA_DIR#./}/ssh:/etc/ssh/keys" \
    -v "$(pwd)/${DATA_DIR#./}/pi:/root/.pi" \
    -v "$(pwd)/${DATA_DIR#./}/gh:/root/.config/gh" \
    "${IMAGE_NAME}:${IMAGE_TAG}"

echo "容器已启动：$CONTAINER_NAME"
echo "SSH：ssh root@localhost -p ${SSH_PORT:-2222}"
echo "Pi 日志：docker exec -it $CONTAINER_NAME tail -f /var/log/pi-remote-feishu/feishu.log"
