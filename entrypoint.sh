#!/usr/bin/env bash
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

: "${SSH_PASSWORD:=}"
: "${DEV_PASSWORD:=}"
: "${DEV_USER:=dev}"
: "${SSH_PERMIT_ROOT_LOGIN:=yes}"
: "${SSH_PASSWORD_AUTH:=yes}"
: "${PI_WORKDIR:=/workspace}"
: "${FEISHU_ENABLED:=auto}"
: "${FEISHU_CONFIG:=}"
: "${FEISHU_GROUP_SCOPE:=shared-chat}"
: "${FEISHU_LOG_LEVEL:=info}"
: "${FEISHU_DEBUG_EVENTS:=0}"
: "${FEISHU_CONFIG_FORCE:=0}"
: "${FEISHU_RESTART_LIMIT:=5}"

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

# ---------- Pi 配置目录 ----------
# 挂载的 $HOME/.pi 为空（新卷）时，用镜像里烘焙的种子填充：
# 其中包含 pi-remote-feishu 扩展与 npm 缓存的包，避免首启再联网安装。
if [ ! -f /root/.pi/agent/settings.json ] && [ -d /opt/pi-seed ]; then
    log "初始化 /root/.pi（从镜像种子复制）"
    mkdir -p /root/.pi
    cp -a /opt/pi-seed/. /root/.pi/
fi

mkdir -p "$PI_WORKDIR"

# ---------- pi-remote-feishu ----------
have_feishu_creds() {
    if [ -n "${FEISHU_APP_ID:-}" ] && [ -n "${FEISHU_APP_SECRET:-}" ]; then
        return 0
    fi
    return 1
}

should_start_feishu() {
    case "$FEISHU_ENABLED" in
        0|false|no|off|"") return 1 ;;
        1|true|yes|on) return 0 ;;
        auto) have_feishu_creds ;;
        *)
            log "FEISHU_ENABLED=${FEISHU_ENABLED} 无法识别，按 auto 处理"
            have_feishu_creds ;;
    esac
}

if should_start_feishu; then
    if [ -z "${FEISHU_APP_ID:-}" ] || [ -z "${FEISHU_APP_SECRET:-}" ]; then
        log "FEISHU_ENABLED=1 但缺少 FEISHU_APP_ID / FEISHU_APP_SECRET，跳过飞书桥接"
    else
        config_path="$FEISHU_CONFIG"
        if [ -z "$config_path" ]; then
            # 由环境变量生成/合并 ~/.pi/agent/feishu.json，并让桥接自动发现
            force_args=()
            [ "$FEISHU_CONFIG_FORCE" = "1" ] && force_args=(--force)
            if ! python3 /usr/local/bin/feishu-config.py --out /root/.pi/agent/feishu.json "${force_args[@]}"; then
                log "生成飞书配置失败，继续用环境变量启动"
            fi
        elif [ ! -f "$config_path" ]; then
            log "FEISHU_CONFIG=$config_path 不存在，改用环境变量启动"
            config_path=""
        fi

        mkdir -p /var/log/pi-remote-feishu
        logfile=/var/log/pi-remote-feishu/feishu.log
        touch "$logfile"

        argv=(serve --cwd "$PI_WORKDIR" --log-level "$FEISHU_LOG_LEVEL" --group-scope "$FEISHU_GROUP_SCOPE")
        [ -n "$config_path" ] && argv+=(--config "$config_path")
        [ "$FEISHU_DEBUG_EVENTS" = "1" ] && argv+=(--debug-events)

        # 桥接进程守护：异常退出后按 15s→300s 退避重启，运行满 2 分钟则重置计数
        log "启动 pi-remote-feishu（workspace=${PI_WORKDIR}, group-scope=${FEISHU_GROUP_SCOPE}）"
        (
            set +e
            attempt=0
            while :; do
                started=$(date +%s)
                pi-remote-feishu "${argv[@]}" >>"$logfile" 2>&1
                code=$?
                ran=$(( $(date +%s) - started ))
                [ "$ran" -ge 120 ] && attempt=0
                attempt=$((attempt + 1))
                if [ "$attempt" -ge "$FEISHU_RESTART_LIMIT" ]; then
                    log "pi-remote-feishu 连续异常退出 ${attempt} 次（最后退出码 ${code}），停止重启；请检查配置后重启容器"
                    exit 0
                fi
                delay=$((attempt * 15))
                [ "$delay" -gt 300 ] && delay=300
                log "pi-remote-feishu 退出（code=${code}，运行 ${ran}s），${delay}s 后重启"
                sleep "$delay"
            done
        ) >>"$logfile" 2>&1 &
        sleep 6
        if pgrep -f "pi-remote-feishu serve" >/dev/null 2>&1; then
            log "pi-remote-feishu 已启动（日志 ${logfile}）"
            log "在飞书里给机器人发消息即可；排障：docker exec -it <容器> pi-remote-feishu doctor --cwd ${PI_WORKDIR}"
        else
            log "pi-remote-feishu 未能保持运行，最近日志："
            tail -n 30 "$logfile" 2>/dev/null || true
        fi
    fi
else
    log "飞书桥接未启用（设置 FEISHU_APP_ID / FEISHU_APP_SECRET 后重启容器即可）"
fi

exec "$@"
