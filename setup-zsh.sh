#!/usr/bin/env bash
# ============================================================================
# setup-zsh.sh — 安装 zsh 并设为默认 shell
#   附带: 历史记录/补全等基础配置，zsh-autosuggestions、
#         zsh-syntax-highlighting（增强包来自 Debian 官方仓库，走清华源，
#         无需访问 GitHub）
# 用法: sudo bash setup-zsh.sh [用户名]
#   未指定用户名时，切换触发 sudo 的真实用户（$SUDO_USER）；root 直接运行须指定
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

if [[ ${EUID} -ne 0 ]]; then
    error "请使用 sudo 运行: sudo bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
info "安装 zsh ..."
apt install -y zsh

info "安装增强包 zsh-autosuggestions / zsh-syntax-highlighting ..."
apt install -y zsh-autosuggestions zsh-syntax-highlighting \
    || warn "增强包安装失败，跳过（不影响 zsh 本体）"

ZSH_BIN="$(command -v zsh)"
grep -qx "${ZSH_BIN}" /etc/shells || echo "${ZSH_BIN}" >> /etc/shells

# sudo 场景下切换的是真实用户（SUDO_USER），而不是 root；
# 也可显式指定用户: sudo bash setup-zsh.sh <用户名>
TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z ${TARGET_USER} || ${TARGET_USER} == "root" ]]; then
    error "未能确定目标用户；请在普通用户下用 sudo 运行，或显式指定: sudo bash $0 <用户名>"
    exit 1
fi
if ! getent passwd "${TARGET_USER}" >/dev/null; then
    error "用户不存在: ${TARGET_USER}"
    exit 1
fi
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

info "将用户 ${TARGET_USER} 的默认 shell 切换为 ${ZSH_BIN} ..."
chsh -s "${ZSH_BIN}" "${TARGET_USER}"

# 若用户没有 .zshrc，则生成一份基础配置（已存在则不覆盖）
if [[ ! -f "${TARGET_HOME}/.zshrc" ]]; then
    cat > "${TARGET_HOME}/.zshrc" <<'ZSHRC'
# ===== 基础 =====
export EDITOR=vim
HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS AUTO_CD

# ===== 补全 =====
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# ===== 按键（bash 习惯）=====
bindkey -e

# ===== starship 提示符（由 setup-ghostty.sh 安装）=====
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# ===== fnm / Node.js（由 setup-fnm.sh 安装）=====
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
    export PATH="$FNM_PATH:$PATH"
    eval "$(fnm env --use-on-cd --shell zsh)"
fi

# ===== Debian 官方增强包（apt 安装，无 GitHub 依赖）=====
# zsh-syntax-highlighting 必须在 .zshrc 末尾 source
[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSHRC
    chown "${TARGET_USER}:" "${TARGET_HOME}/.zshrc"
    info "已生成 ${TARGET_HOME}/.zshrc"
else
    warn "已存在 ${TARGET_HOME}/.zshrc，保持不变"
fi

info "完成！注销重新登录后默认 shell 生效（当前会话可先执行: exec zsh）"
