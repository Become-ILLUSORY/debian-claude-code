# debian-claude-code

Debian 13 (trixie) 容器镜像，内置 Claude Code、cc-connect 与 SSH 服务，apt 源已换成清华镜像。

## 内容

| 组件 | 说明 |
| --- | --- |
| 基础镜像 | `debian:trixie-slim`，apt 使用 `mirrors.tuna.tsinghua.edu.cn` |
| Node.js | v22.23.3，从清华 `nodejs-release` 镜像下载并校验 sha256（Debian 13 自带的 20 不满足 claude-code 的 `>=22` 要求） |
| Claude Code | `@anthropic-ai/claude-code`（npm，原生二进制） |
| cc-connect | v1.5.0 Go 二进制，优先 GitHub Releases，失败自动回退 Gitee |
| SSH | openssh-server，密码/公钥均可在运行时通过环境变量注入 |
| 其他 | git、git-lfs、gh、python3+venv+pip、curl、wget、jq、tree、unzip、ripgrep、fd、bat、vim、nano、tmux、zsh、htop、mosh、build-essential |

## 构建

```bash
./build.sh
# 或
docker build -t debian-claude-code:latest .
```

常用 `--build-arg`：

| 参数 | 默认值 |
| --- | --- |
| `DEBIAN_VERSION` | `trixie-slim` |
| `NODE_VERSION` | `22.23.3` |
| `CLAUDE_CODE_VERSION` | `latest` |
| `CC_CONNECT_VERSION` | `1.5.0` |
| `DEV_UID` / `DEV_GID` | `1000` / `1000` |
| `NPM_REGISTRY` | `https://registry.npmmirror.com` |

构建过程说明：基础镜像没有 CA 证书，直接换 `https` 清华源会因证书校验失败导致 `apt-get update` 全部忽略；因此第一步先用 `http` 拉取并安装 `ca-certificates`，再切回 `https`。

## 运行

两种方式任选：

```bash
cp .env.example .env
# 按需修改 .env（SSH 密码、API 地址等）

# 方式一：docker compose（需 docker compose 插件）
docker compose up -d

# 方式二：没有 compose 插件时
./run.sh
```

SSH 登录（默认映射到宿主的 2222 端口）：

```bash
ssh root@localhost -p 2222          # 密码取自 .env 的 SSH_PASSWORD
ssh dev@localhost -p 2222           # 密码取自 .env 的 DEV_PASSWORD，可 sudo
```

进入容器直接使用 Claude Code：

```bash
docker compose exec claude bash -lc 'claude'
```

## 环境变量

| 变量 | 说明 |
| --- | --- |
| `SSH_PASSWORD` | root 的 SSH 密码；留空则不设置 |
| `DEV_PASSWORD` | `dev` 用户的密码 |
| `SSH_AUTHORIZED_KEYS` | 公钥内容，写入 root 与 dev 的 `authorized_keys` |
| `SSH_PERMIT_ROOT_LOGIN` / `SSH_PASSWORD_AUTH` | 覆盖 sshd 配置，默认 `yes` |
| `CC_CONNECT_ENABLED` | `1` 时随容器启动 cc-connect |
| `CC_CONNECT_USER` | cc-connect 运行用户，默认 `root` |
| `CC_CONNECT_CONFIG` | 指定 config.toml 路径，默认 `~/.cc-connect/config.toml` |
| `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` | 直接透传给 Claude Code |

## cc-connect

首次启动会在 `~/.cc-connect/config.toml` 生成模板并随即退出（缺 agent 平台凭据），容器日志会给出提示。配好后再 `docker restart`：

```bash
docker compose exec claude cc-connect web   # 网页配置，或直接编辑 config.toml
docker compose restart claude
```

模板里的 `work_dir` 要改成容器内真实存在的目录（如 `/workspace`），否则 cc-connect 报 `work_dir does not exist` 并退出。管理面板监听 9820（已在 compose 中映射），bridge 监听 9810。日志在容器的 `/var/log/cc-connect/cc-connect.log`。

在 Claude Code 会话内启动 cc-connect 会因 `CLAUDECODE` 环境变量被拒绝，entrypoint 已用 `env -u CLAUDECODE` 处理；手动启动时请先 `unset CLAUDECODE`。

## 数据持久化

compose 把以下路径映射到 `./data/`：

- `workspace/` → `/workspace`（工作目录）
- `ssh/` → `/etc/ssh/keys`（SSH 主机密钥，删除后重建会变更）
- `root-claude/` → `/root/.claude`（Claude Code 登录态与配置）
- `root-cc-connect/` → `/root/.cc-connect`（cc-connect 配置与会话）
- `root-gh/` → `/root/.config/gh`（gh 登录态）

日志目录 `/var/log` 单独用命名卷 `cc-connect-log` 承载，避免覆盖镜像内系统日志。
