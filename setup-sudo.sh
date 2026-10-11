#!/usr/bin/env bash
# ============================================================================
# setup-sudo.sh — 将指定用户加入 sudo 组，获得管理员权限
#   幂等：已在 sudo 组则跳过；自动校验 /etc/sudoers 中的 %sudo 规则
# 用法:
#   sudo bash setup-sudo.sh            # 提升触发 sudo 的真实用户
#   sudo bash setup-sudo.sh <用户名>   # 提升指定用户
#   （若系统还没装 sudo / 没有任何 sudo 用户，可用 root 登录后运行本脚本）
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ ${EUID} -ne 0 ]]; then
    error "请使用 sudo 运行: sudo bash $0 [用户名]"
    exit 1
fi

# ---------- 1. 确定目标用户: 参数 > $SUDO_USER ----------
TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z ${TARGET_USER} ]]; then
    error "未能确定目标用户，请显式指定: sudo bash $0 <用户名>"
    echo "系统中的普通用户（UID>=1000）:" >&2
    awk -F: '$3>=1000 && $3<65534 {print "    "$1" (uid="$3")"}' /etc/passwd >&2
    exit 1
fi
if ! getent passwd "${TARGET_USER}" >/dev/null; then
    error "用户不存在: ${TARGET_USER}"
    exit 1
fi

# ---------- 2. 确保 sudo 已安装（最小化安装的 Debian 可能没有） ----------
if ! command -v sudo >/dev/null 2>&1; then
    info "sudo 未安装，正在安装 ..."
    export DEBIAN_FRONTEND=noninteractive
    apt update
    apt install -y sudo
fi

# ---------- 3. 校验 sudoers 中启用了 %sudo 组规则 ----------
if ! grep -rEq '^[[:space:]]*%sudo[[:space:]]' /etc/sudoers /etc/sudoers.d/ 2>/dev/null; then
    warn "/etc/sudoers 中未找到 %sudo 规则，正在添加 ..."
    echo '%sudo ALL=(ALL:ALL) ALL' > /etc/sudoers.d/sudo-group
    chmod 440 /etc/sudoers.d/sudo-group
    visudo -c
fi

# ---------- 4. 加入 sudo 组（幂等） ----------
if id -nG "${TARGET_USER}" | grep -qw sudo; then
    info "用户 ${TARGET_USER} 已在 sudo 组，无需修改"
else
    usermod -aG sudo "${TARGET_USER}"
    info "已将 ${TARGET_USER} 加入 sudo 组"
fi

info "完成！请重新登录（或运行 newgrp sudo）使组变更生效"
info "生效后验证: sudo whoami   # 应输出 root"
