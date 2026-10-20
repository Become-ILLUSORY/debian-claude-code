# syntax=docker/dockerfile:1

ARG DEBIAN_VERSION=trixie-slim
FROM debian:${DEBIAN_VERSION}

ARG DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn
ARG NODE_VERSION=22.23.3
ARG NPM_REGISTRY=https://registry.npmmirror.com
ARG CLAUDE_CODE_VERSION=latest
ARG CC_CONNECT_VERSION=1.5.0
ARG TARGETARCH
ARG DEV_UID=1000
ARG DEV_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Shanghai \
    NPM_CONFIG_REGISTRY=${NPM_REGISTRY}

# 换成清华源（trixie 使用 deb822 格式的 debian.sources）
# 镜像里还没有 CA 证书，先用 http 拉一次装好 ca-certificates，再切回 https
RUN set -eux; \
    src=/etc/apt/sources.list.d/debian.sources; \
    sed -i -E "s#https?://(deb|security)\.debian\.org#http://${DEBIAN_MIRROR#*://}#g" "$src"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    sed -i -E "s#http://${DEBIAN_MIRROR#*://}#${DEBIAN_MIRROR}#g" "$src"; \
    apt-get update; \
    rm -rf /var/lib/apt/lists/*; \
    cat "$src"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash-completion ca-certificates curl wget gnupg \
        git git-lfs gh \
        openssh-server openssh-client mosh \
        tini gosu sudo \
        python3 python3-venv python3-pip \
        jq tree less unzip zip xz-utils file tar gzip \
        ripgrep fd-find bat htop procps iproute2 bind9-dnsutils \
        vim nano tmux zsh bash tzdata \
        build-essential; \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Node.js（Debian 13 自带 20，claude-code 要求 >= 22）
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) node_arch=x64 ;; \
        arm64) node_arch=arm64 ;; \
        *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    base="${DEBIAN_MIRROR}/nodejs-release/v${NODE_VERSION}"; \
    tarball="node-v${NODE_VERSION}-linux-${node_arch}.tar.xz"; \
    curl -fsSL --retry 3 --connect-timeout 20 "$base/SHASUMS256.txt" -o /tmp/SHASUMS256.txt; \
    curl -fsSL --retry 3 --connect-timeout 20 "$base/$tarball" -o "/tmp/$tarball"; \
    (cd /tmp && grep " ${tarball}\$" SHASUMS256.txt | sha256sum -c -); \
    tar -xJf "/tmp/$tarball" -C /usr/local --strip-components=1 --no-same-owner; \
    rm -f "/tmp/$tarball" /tmp/SHASUMS256.txt; \
    node -v; npm -v

# Claude Code（npm 原生二进制包）
RUN set -eux; \
    npm install -g --no-audit --no-fund "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"; \
    claude --version; \
    npm cache clean --force

# cc-connect（Go 二进制，GitHub Releases 优先，Gitee 自动回退）
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    tmp=/tmp/cc-connect; mkdir -p "$tmp"; \
    for url in \
      "https://github.com/chenhg5/cc-connect/releases/download/v${CC_CONNECT_VERSION}/cc-connect-v${CC_CONNECT_VERSION}-linux-${arch}.tar.gz" \
      "https://gitee.com/cg33/cc-connect/releases/download/v${CC_CONNECT_VERSION}/cc-connect-v${CC_CONNECT_VERSION}-linux-${arch}.tar.gz"; do \
        echo "trying $url"; \
        if curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$tmp/cc.tar.gz"; then break; fi; \
    done; \
    test -s "$tmp/cc.tar.gz"; \
    tar -xzf "$tmp/cc.tar.gz" -C "$tmp"; \
    install -m 0755 "$tmp/cc-connect-v${CC_CONNECT_VERSION}-linux-${arch}" /usr/local/bin/cc-connect; \
    rm -rf "$tmp"; \
    cc-connect --version

# 用户与目录（uid/gid 与宿主一致，方便挂载）
RUN set -eux; \
    if ! getent group "${DEV_GID}" >/dev/null; then groupadd -g "${DEV_GID}" dev; fi; \
    if ! getent passwd "${DEV_UID}" >/dev/null; then \
        useradd -m -u "${DEV_UID}" -g "$(getent group "${DEV_GID}" | cut -d: -f1)" -s /bin/bash dev; \
    fi; \
    dev_user="$(getent passwd "${DEV_UID}" | cut -d: -f1)"; \
    echo "${dev_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-dev; \
    chmod 0440 /etc/sudoers.d/90-dev; \
    mkdir -p /workspace /run/sshd /etc/ssh/keys /root/.cc-connect /root/.claude; \
    chown -R "${DEV_UID}:${DEV_GID}" /workspace; \
    chmod 700 /root

# sshd：容器内允许 root 密码登录，宿主密钥目录可挂载持久化
COPY sshd-container.conf /etc/ssh/sshd_config.d/00-container.conf
# 去掉镜像内烘焙的默认主机密钥，改为启动时在 /etc/ssh/keys 生成（可挂载持久化）
RUN set -eux; \
    chmod 600 /etc/ssh/sshd_config.d/00-container.conf; \
    sed -i 's|^HostKey /etc/ssh/ssh_host_|#&|' /etc/ssh/sshd_config; \
    rm -f /etc/ssh/ssh_host_*

COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

WORKDIR /workspace

EXPOSE 22 9810 9820

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/22' || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["sleep", "infinity"]
