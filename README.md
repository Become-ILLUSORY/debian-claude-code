# debian-pi-agent

Debian 13 (trixie) 容器镜像，内置 **Pi Agent**、**pi-remote-feishu 飞书桥接** 与 SSH 服务，apt 源已换成清华镜像。

> 这个仓库原来叫 `debian-claude-code`（Claude Code + cc-connect）。现已整体转向 **Pi Agent**：
> Claude Code → `@earendil-works/pi-coding-agent`，cc-connect → `pi-remote-feishu`。
> 旧的 cc-connect 管理端口 9810/9820 一并移除，飞书桥接走 WebSocket 长连接，无需公网入口。

## 内容

| 组件 | 说明 |
| --- | --- |
| 基础镜像 | `debian:trixie-slim`，apt 使用 `mirrors.tuna.tsinghua.edu.cn` |
| Node.js | v22.23.3，从清华 `nodejs-release` 镜像下载并校验 sha256（Debian 13 自带 20，不满足 Pi 的 `>=22.19`） |
| Pi Agent | `@earendil-works/pi-coding-agent`（npm 全局，`pi` 命令） |
| 飞书桥接 | `pi-remote-feishu`（npm 全局，`pi-remote-feishu` 命令），同时注册为 Pi 扩展 |
| SSH | openssh-server，密码/公钥均可在运行时通过环境变量注入 |
| 其他 | git、git-lfs、gh、python3+venv+pip、curl、wget、jq、tree、unzip、ripgrep、fd、bat、vim、nano、tmux、zsh、htop、mosh、build-essential |

## 直接使用（预构建镜像）

GitHub Actions 已构建 `linux/amd64` 与 `linux/arm64` 双架构镜像并推送到 ghcr.io：

```bash
docker pull ghcr.io/become-illusory/debian-pi-agent:latest
```

不想自己写参数就用 compose / 脚本（见下文「运行」）。

## 飞书机器人配置（关键一步）

1. 打开 [飞书开放平台](https://open.feishu.cn/app) → 创建**企业自建应用**。
2. 「添加应用能力」→ 开启 **机器人**。
3. 「权限管理」至少开通：
   - `im:message`（读取与发送消息）
   - `im:message:send_as_bot`（以机器人身份发消息）
   - `im:resource`（上传/下载图片与文件，`send_file_to_chat` 需要）
4. 「事件订阅」→ 订阅方式选 **使用长连接接收事件**，并添加事件：
   - `im.message.receive_v1`（接收消息）
   - `card.action.trigger`（卡片回传交互，`/models`、`/sessions` 等卡片按钮依赖它）
5. 「版本管理与发布」→ 创建版本并发布（企业内需管理员审核通过）。
6. 「凭证与基础信息」里复制 **App ID / App Secret**，填进 `.env` 的 `FEISHU_APP_ID` / `FEISHU_APP_SECRET`。

镜像启动后会自动用环境变量生成 `~/.pi/agent/feishu.json`（已存在的配置会保留手工修改），并拉起桥接进程。
配好后在飞书里私聊机器人，或群里 @机器人 说话即可。

## 运行

```bash
cp .env.example .env
# 填 FEISHU_APP_ID / FEISHU_APP_SECRET，按需改 SSH 密码、模型 API Key

# 方式一：docker compose（需 docker compose 插件）
docker compose up -d

# 方式二：没有 compose 插件时
./run.sh
```

也可以 `docker run` 直接起：

```bash
docker run -d --name pi-agent \
  -p 2222:22 \
  -e SSH_PASSWORD=debian -e DEV_PASSWORD=debian \
  -e FEISHU_APP_ID=cli_xxx -e FEISHU_APP_SECRET=xxx \
  -e ANTHROPIC_API_KEY=sk-ant-xxx \
  -v "$PWD/data/workspace:/workspace" \
  -v "$PWD/data/ssh:/etc/ssh/keys" \
  -v "$PWD/data/pi:/root/.pi" \
  ghcr.io/become-illusory/debian-pi-agent:latest
```

镜像标签：`latest`（默认分支）、`main`、`v1.2.3` / `v1.2` / `v1`（推送 `v*` tag 时自动生成）。

## 从源码构建

```bash
./build.sh
# 或
docker build -t debian-pi-agent:latest .
```

常用 `--build-arg`：

| 参数 | 默认值 |
| --- | --- |
| `DEBIAN_VERSION` | `trixie-slim` |
| `NODE_VERSION` | `22.23.3` |
| `PI_VERSION` | `latest` |
| `PI_REMOTE_FEISHU_VERSION` | `latest` |
| `PI_FEISHU_EXTENSION` | `1`（把 pi-remote-feishu 注册为 Pi 扩展） |
| `DEV_UID` / `DEV_GID` | `1000` / `1000` |
| `NPM_REGISTRY` | `https://registry.npmmirror.com` |

构建过程说明：基础镜像没有 CA 证书，直接换 `https` 清华源会因证书校验失败导致 `apt-get update` 全部忽略；因此第一步先用 `http` 拉取并安装 `ca-certificates`，再切回 `https`。

`pi install npm:pi-remote-feishu` 装出来的 `~/.pi`（含扩展与依赖包，约 200MB）会被挪到 `/opt/pi-seed`；
首次启动若 `data/pi` 是空卷，entrypoint 会自动复制回去，无需再联网安装。

## 环境变量

### SSH

| 变量 | 说明 |
| --- | --- |
| `SSH_PASSWORD` | root 的 SSH 密码；留空则不设置 |
| `DEV_PASSWORD` | `dev` 用户的密码 |
| `SSH_AUTHORIZED_KEYS` | 公钥内容，写入 root 与 dev 的 `authorized_keys` |
| `SSH_PERMIT_ROOT_LOGIN` / `SSH_PASSWORD_AUTH` | 覆盖 sshd 配置，默认 `yes` |
| `SSH_PORT` | compose/run.sh 里宿主映射端口，默认 2222 |

### Pi

| 变量 | 说明 |
| --- | --- |
| `PI_WORKDIR` | Pi 工作目录，默认 `/workspace`（也是飞书会话默认 cwd） |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `GEMINI_API_KEY` / `DEEPSEEK_API_KEY` / `OPENROUTER_API_KEY` | 模型凭据，Pi 直接读取；也可用 `docker exec -it pi-agent pi` 登录订阅账号 |

### 飞书桥接

| 变量 | 说明 |
| --- | --- |
| `FEISHU_ENABLED` | `auto`（默认，填了 appId/appSecret 才启动）\| `1` 强制 \| `0` 关闭 |
| `FEISHU_APP_ID` / `FEISHU_APP_SECRET` | 飞书应用凭证 |
| `FEISHU_BOT_NAME` | 机器人显示名，默认 `Pi Agent` |
| `FEISHU_CONFIG` | 指定容器内配置文件路径；留空则由环境变量生成 `~/.pi/agent/feishu.json` |
| `FEISHU_CONFIG_FORCE` | `1` 时用环境变量整体重写配置（默认只合并且保留手工修改） |
| `FEISHU_GROUP_SCOPE` | `shared-chat`（整群共享一个会话，默认）\| `per-user`（群内按人隔离） |
| `FEISHU_REQUIRE_MENTION` | 群聊是否必须 @机器人，默认 `1` |
| `FEISHU_DM_ENABLED` / `FEISHU_GROUP_ENABLED` | 是否响应私聊 / 群聊，默认都开 |
| `FEISHU_ALLOW_USERS` / `FEISHU_ALLOW_CHATS` | 白名单（open_id / chat_id，逗号分隔），留空不限制 |
| `FEISHU_RENDERING_MODE` | `stream-card`（默认，流式卡片）\| `markdown` \| `text` |
| `FEISHU_LOG_LEVEL` | `fatal\|error\|warn\|info\|debug\|trace`，默认 `info` |
| `FEISHU_DEBUG_EVENTS` | `1` 时打印收到的消息/卡片事件摘要 |
| `FEISHU_MAX_UPLOAD_MB` | 上传/回传文件大小上限，默认 20 |
| `FEISHU_RESTART_LIMIT` | 桥接连续异常退出后的最大重启次数，默认 5（15s→300s 退避） |

`FEISHU_ALLOWED_OUTPUT_DIRS`、`FEISHU_IDLE_TTL_MIN`、`FEISHU_RENDERING_MODE` 等也能通过环境变量写进配置，见 `feishu-config.py`。

## 使用

进入容器跑 Pi 的终端界面（选模型、开会话、装包）：

```bash
ssh root@localhost -p 2222
pi
```

飞书聊天里可用的命令：

| 命令 | 说明 |
| --- | --- |
| `/help` | 查看帮助 |
| `/sessions` | 查看/切换/删除会话 |
| `/models` | 选择模型与思考等级 |
| `/new` | 新建 Pi 会话 |
| `/stop` | 停止当前生成 |
| `/reset` | 重置当前会话映射 |
| `/status` | 连接/队列/模型状态 |

模型把生成的文件发回聊天：模型调用 `send_file_to_chat` 工具（受输出目录白名单与大小上限限制）。

## 数据持久化

compose 把以下路径映射到 `./data/`：

- `workspace/` → `/workspace`（工作目录）
- `ssh/` → `/etc/ssh/keys`（SSH 主机密钥，删除后重建会变更）
- `pi/` → `/root/.pi`（Pi 登录态、settings、会话记录、飞书会话映射 `feishu/sessions.json`）
- `gh/` → `/root/.config/gh`（gh 登录态）

日志目录 `/var/log` 单独用命名卷 `pi-log` 承载，飞书桥接日志在 `/var/log/pi-remote-feishu/feishu.log`。

## 排障

```bash
# 容器启动日志（会打印 SSH / 飞书桥接状态）
docker logs pi-agent

# 桥接日志
docker exec -it pi-agent tail -f /var/log/pi-remote-feishu/feishu.log

# 配置与长连接自检
docker exec -it pi-agent pi-remote-feishu doctor --cwd /workspace

# 往指定会话发一条测试消息（chat_id 从日志或开放平台拿）
docker exec -it pi-agent pi-remote-feishu send-test --chat-id oc_xxx --text "hello"
```

常见问题：

- **日志出现 `Missing Feishu appId`**：`FEISHU_APP_ID`/`FEISHU_APP_SECRET` 没传进容器，或 `FEISHU_ENABLED=0`。
- **`could not resolve bot identity ... status: 400`**：凭证错、应用未发布，或机器人能力没开。
- **机器人收不到消息**：事件订阅没选「长连接」，或没订阅 `im.message.receive_v1`。
- **卡片按钮没反应**：没订阅 `card.action.trigger`，或应用权限未生效（改权限后需重新发布版本）。
- **模型报未配置**：在容器里 `pi` 进 TUI 用 `/models` 选一个已配好凭据的模型，或设置对应 `*_API_KEY` 后重启容器。

## 与上游的关系

- 桥接本体是第三方包 [pi-remote-feishu](https://pi.dev/packages/pi-remote-feishu)（MIT），由它自带的 Pi SDK 版本（当前 0.83.0）在进程内驱动会话；
  镜像里的 `pi` 命令是独立安装的（默认 `latest`）。两者会话格式版本一致（`SESSION_VERSION=3`），
  但若上游后续改版出现会话不兼容，可用 `--build-arg PI_VERSION=0.83.0` 把全局 `pi` 固定到桥接自带 SDK 的同版本。
- Pi Agent 文档：<https://pi.dev/docs>；包列表：<https://pi.dev/packages>
