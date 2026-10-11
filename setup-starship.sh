#!/usr/bin/env bash
# ============================================================================
# setup-starship.sh — 安装 Starship 提示符
#
#   官方安装脚本托管在 starship.rs（国内访问慢），已下载到
#   assets/starship-install.sh，并给脚本内部的 GitHub 下载地址加了
#   gh-proxy 前缀（脚本源码在本地，可自由修改）。
#
# 用法: sudo bash setup-starship.sh [用户名]
#   .zshrc 配置写入目标用户家目录；未指定时用 $SUDO_USER，root 直接运行须指定
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID} -ne 0 ]]; then
    error "请使用 sudo 运行: sudo bash $0"
    exit 1
fi
if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != "root" ]]; then
    TARGET_USER="${SUDO_USER}"
else
    TARGET_USER=""
fi
# 也可显式指定用户: sudo bash setup-starship.sh <用户名>
if [[ $# -ge 1 ]]; then
    TARGET_USER="$1"
fi
if [[ -z ${TARGET_USER} ]]; then
    error "未能确定目标用户；请在普通用户下用 sudo 运行，或显式指定: sudo bash $0 <用户名>"
    exit 1
fi
if ! getent passwd "${TARGET_USER}" >/dev/null; then
    error "用户不存在: ${TARGET_USER}"
    exit 1
fi
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

# ---------- 1. 安装 starship ----------
install_starship() {
    if command -v starship >/dev/null 2>&1; then
        info "starship 已安装: $(command -v starship)"
        return 0
    fi
    local installer="${SCRIPT_DIR}/assets/starship-install.sh"
    if [[ -f ${installer} ]]; then
        info "使用本地改写版安装脚本（内部 GitHub 地址已加 gh-proxy 前缀）..."
        # 注意: 官方脚本要求用 POSIX sh 执行（bash 非严格模式会被它主动拒绝）
        sh "${installer}" --yes
    else
        warn "未找到 ${installer}，回退官方在线脚本（国内可能较慢）..."
        curl -fsSL https://starship.rs/install.sh | sh -s -- --yes \
            --base-url "https://gh-proxy.com/https://github.com/starship/starship/releases"
    fi
}

install_starship || { error "starship 安装失败"; exit 1; }

# ---------- 2. 配置 .zshrc ----------
# 确保 zsh 启用 starship（.zshrc 已存在且没有相应配置时追加）
ZRC="${TARGET_HOME}/.zshrc"
if [[ -f ${ZRC} ]] && ! grep -q 'starship init zsh' "${ZRC}"; then
    cat >> "${ZRC}" <<'EOF'

# starship 提示符
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi
EOF
    chown "${TARGET_USER}:" "${ZRC}"
    info "已在 ${ZRC} 中追加 starship 初始化"
fi

info "完成！提示符: starship（重新打开终端生效）"
