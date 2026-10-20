#!/usr/bin/env bash
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

: "${SSH_PASSWORD:=}"
: "${DEV_PASSWORD:=}"
: "${DEV_USER:=dev}"
: "${SSH_PERMIT_ROOT_LOGIN:=yes}"
: "${SSH_PASSWORD_AUTH:=yes}"
: "${CC_CONNECT_ENABLED:=0}"
: "${CC_CONNECT_USER:=root}"
: "${CC_CONNECT_CONFIG:=}"

# ---------- SSH ----------
mkdir -p /run/sshd /etc/ssh/keys /root/.ssh
chmod 700 /root/.ssh /etc/ssh/keys

gen_key() {
    local type=$1 path=$2
    [ -s "$path" ] || ssh-keygen -q -t "$type" -N '' -f "$path" -C "root@$(hostname)"
}

gen_key ed25519 /etc/ssh/keys/ssh_host_ed25519_key
gen_key rsa /etc/ssh/keys/ssh_host_rsa_key
chmod 600 /etc/ssh/keys/ssh_host_*_key
chmod 644 /etc/ssh/keys/ssh_host_*.pub

if [ -n "$SSH_PASSWORD" ]; then
    echo "root:${SSH_PASSWORD}" | chpasswd
    log "root 密码已设置"
fi

if [ -n "$DEV_PASSWORD" ]; then
    echo "${DEV_USER}:${DEV_PASSWORD}" | chpasswd
    log "${DEV_USER} 密码已设置"
fi

# 支持 SSH_AUTHORIZED_KEYS 环境变量（多行）或 /etc/ssh/authorized_keys 挂载文件
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
    printf '%s\n' "$SSH_AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi
if [ -s /etc/ssh/authorized_keys ]; then
    install -m 600 /etc/ssh/authorized_keys /root/.ssh/authorized_keys
    if id "$DEV_USER" >/dev/null 2>&1; then
        install -d -m 700 -o "$DEV_USER" -g "$(id -gn "$DEV_USER")" "/home/${DEV_USER}/.ssh"
        install -m 600 -o "$DEV_USER" -g "$(id -gn "$DEV_USER")" /etc/ssh/authorized_keys "/home/${DEV_USER}/.ssh/authorized_keys"
    fi
fi

sed -i -E "s/^PermitRootLogin .*/PermitRootLogin ${SSH_PERMIT_ROOT_LOGIN}/" /etc/ssh/sshd_config.d/00-container.conf
sed -i -E "s/^PasswordAuthentication .*/PasswordAuthentication ${SSH_PASSWORD_AUTH}/" /etc/ssh/sshd_config.d/00-container.conf
/usr/sbin/sshd -t
mkdir -p /run/sshd
/usr/sbin/sshd -e
log "sshd 已启动 (22)"

# ---------- cc-connect ----------
if [ "$CC_CONNECT_ENABLED" = "1" ]; then
    cfg_args=()
    if [ -n "$CC_CONNECT_CONFIG" ]; then
        cfg_args=(-config "$CC_CONNECT_CONFIG")
    fi
    target_home=/root
    if [ "$CC_CONNECT_USER" != "root" ]; then
        target_home="/home/${CC_CONNECT_USER}"
    fi
    mkdir -p "${target_home}/.cc-connect"
    chown -R "${CC_CONNECT_USER}:${CC_CONNECT_USER}" "${target_home}/.cc-connect" 2>/dev/null || true
    mkdir -p /var/log/cc-connect; touch /var/log/cc-connect/cc-connect.log
    chown -R "${CC_CONNECT_USER}:${CC_CONNECT_USER}" /var/log/cc-connect 2>/dev/null || true

    # cc-connect 拒绝在 Claude Code 会话里拉起子进程，需清掉 CLAUDECODE
    env -u CLAUDECODE gosu "${CC_CONNECT_USER}" \
        cc-connect "${cfg_args[@]}" >>/var/log/cc-connect/cc-connect.log 2>&1 &
    cc_pid=$!
    sleep 3
    if kill -0 "$cc_pid" 2>/dev/null; then
        log "cc-connect 已启动 (用户 ${CC_CONNECT_USER}, 日志 /var/log/cc-connect/cc-connect.log)"
    else
        log "cc-connect 已退出，通常是配置文件还没填好："
        log "  1) docker exec -it <容器> cc-connect web   或编辑 ~/.cc-connect/config.toml"
        log "  2) docker restart <容器>"
        tail -n 20 /var/log/cc-connect/cc-connect.log
    fi
fi

exec "$@"
