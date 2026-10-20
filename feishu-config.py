#!/usr/bin/env python3
"""从环境变量生成/合并 pi-remote-feishu 配置文件。

- 只覆盖显式设置过的环境变量，保留用户手工编辑的其他字段
- --force 时整体重写为环境变量推导出的默认值
- 输出默认为 $HOME/.pi/agent/feishu.json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

TRUE = {"1", "true", "yes", "on", "y"}
FALSE = {"0", "false", "no", "off", "n"}


def env(name: str) -> str | None:
    value = os.environ.get(name)
    if value is None:
        return None
    value = value.strip()
    return value or None


def as_bool(name: str) -> bool | None:
    raw = env(name)
    if raw is None:
        return None
    low = raw.lower()
    if low in TRUE:
        return True
    if low in FALSE:
        return False
    raise SystemExit(f"{name} 需要是布尔值（1/0/true/false），收到：{raw!r}")


def as_int(name: str) -> int | None:
    raw = env(name)
    if raw is None:
        return None
    try:
        return int(raw)
    except ValueError:
        raise SystemExit(f"{name} 需要是整数，收到：{raw!r}")


def as_list(name: str) -> list[str] | None:
    raw = env(name)
    if raw is None:
        return None
    return [item.strip() for item in raw.split(",") if item.strip()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", help="配置输出路径，默认 $HOME/.pi/agent/feishu.json")
    parser.add_argument("--force", action="store_true", help="忽略已有配置，整体重写")
    args = parser.parse_args()

    home = Path(os.environ.get("HOME") or "/root")
    out = Path(args.out) if args.out else home / ".pi" / "agent" / "feishu.json"
    workdir = env("PI_WORKDIR") or "/workspace"
    state_dir = env("FEISHU_STATE_DIR") or str(home / ".pi" / "feishu")

    config: dict = {}
    if out.exists() and not args.force:
        try:
            config = json.loads(out.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            print(f"[feishu-config] 忽略损坏的配置：{out}", file=sys.stderr)
            config = {}

    def put(section: str | None, key: str, value):
        if value is None:
            return
        if section is None:
            config[key] = value
        else:
            config.setdefault(section, {})[key] = value

    # 顶层
    put(None, "appId", env("FEISHU_APP_ID"))
    put(None, "appSecret", env("FEISHU_APP_SECRET"))
    put(None, "botName", env("FEISHU_BOT_NAME"))
    put(None, "encryptKey", env("FEISHU_ENCRYPT_KEY"))
    put(None, "verificationToken", env("FEISHU_VERIFICATION_TOKEN"))
    put(None, "transport", env("FEISHU_TRANSPORT"))

    # policy
    put("policy", "requireMention", as_bool("FEISHU_REQUIRE_MENTION"))
    put("policy", "dmEnabled", as_bool("FEISHU_DM_ENABLED"))
    put("policy", "groupEnabled", as_bool("FEISHU_GROUP_ENABLED"))
    put("policy", "allowUsers", as_list("FEISHU_ALLOW_USERS"))
    put("policy", "allowChats", as_list("FEISHU_ALLOW_CHATS"))

    # sessions
    put("sessions", "groupScope", env("FEISHU_GROUP_SCOPE"))
    put("sessions", "defaultCwd", workdir)
    ttl = as_int("FEISHU_IDLE_TTL_MIN")
    put("sessions", "idleTtlMs", ttl * 60 * 1000 if ttl else None)

    # rendering
    put("rendering", "mode", env("FEISHU_RENDERING_MODE"))
    put("rendering", "showThinking", env("FEISHU_SHOW_THINKING"))
    put("rendering", "showToolEvents", as_bool("FEISHU_SHOW_TOOL_EVENTS"))

    # files
    dirs = as_list("FEISHU_ALLOWED_OUTPUT_DIRS")
    put("files", "allowedOutputDirs", dirs if dirs else [workdir])
    mb = as_int("FEISHU_MAX_UPLOAD_MB")
    put("files", "maxUploadBytes", mb * 1024 * 1024 if mb else None)
    put("files", "tempDir", state_dir)

    # debug
    put("debug", "logIncomingEvents", as_bool("FEISHU_DEBUG_EVENTS"))

    # 默认值补齐（仅在新建时）
    config.setdefault("botName", "Pi Agent")
    config.setdefault("transport", "websocket")
    config.setdefault("policy", {})
    for key, value in (
        ("requireMention", True),
        ("dmEnabled", True),
        ("groupEnabled", True),
    ):
        config["policy"].setdefault(key, value)
    config.setdefault("sessions", {})
    config["sessions"].setdefault("groupScope", "shared-chat")
    config["sessions"].setdefault("defaultCwd", workdir)
    config["sessions"].setdefault("store", "json")
    config.setdefault("rendering", {})
    config["rendering"].setdefault("mode", "stream-card")
    config["rendering"].setdefault("showThinking", "quote")
    config["rendering"].setdefault("showToolEvents", True)
    config.setdefault("files", {})
    config["files"].setdefault("allowedOutputDirs", [workdir])
    config["files"].setdefault("maxUploadBytes", 20 * 1024 * 1024)
    config["files"].setdefault("tempDir", state_dir)

    if not config.get("appId") or not config.get("appSecret"):
        print("[feishu-config] 警告：appId / appSecret 仍未设置", file=sys.stderr)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(out, 0o600)
    Path(str(config["files"]["tempDir"])).mkdir(parents=True, exist_ok=True)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
