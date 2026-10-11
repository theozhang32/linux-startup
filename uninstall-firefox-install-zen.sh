#!/usr/bin/env bash
# ============================================================================
# uninstall-firefox-install-zen.sh — 卸载 firefox-esr，安装 Zen Browser
#   安装逻辑使用 Zen 官方 install.sh（assets/zen-install.sh 本地化版本，
#   仅改写 GitHub 下载地址加 gh-proxy 前缀）。
#   官方脚本为用户级安装：~/.tarball-installations/zen + ~/.local/bin/zen
# 用法: sudo bash uninstall-firefox-install-zen.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZEN_INSTALLER="${SCRIPT_DIR}/assets/zen-install.sh"

if [[ ${EUID} -ne 0 ]]; then
    error "请使用 sudo 运行: sudo bash $0"
    exit 1
fi
export DEBIAN_FRONTEND=noninteractive

# 真实用户（sudo 场景下官方脚本需以普通用户身份运行，否则装进 /root）
REAL_USER="${SUDO_USER:-}"
if [[ -z ${REAL_USER} ]]; then
    error "请勿直接以 root 登录运行；请在普通用户下用 sudo 运行本脚本"
    exit 1
fi
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
[[ -z ${REAL_HOME} ]] && { error "无法确定用户 ${REAL_USER} 的主目录"; exit 1; }

# ---------- 1. 卸载 firefox-esr（仅卸载实际已安装的包） ----------
mapfile -t FF_PKGS < <(dpkg-query -W -f='${binary:Package}\t${Status}\n' 2>/dev/null \
    | awk -F'\t' '$2=="install ok installed" && \
                  $1~/^firefox(-esr)?(:[a-z0-9]+)?(-|$)/ {print $1}' || true)
if ((${#FF_PKGS[@]} > 0)); then
    info "卸载: ${FF_PKGS[*]}"
    apt purge -y "${FF_PKGS[@]}"
    apt autoremove -y || true
else
    info "未检测到已安装的 firefox-esr，跳过卸载"
fi

# ---------- 2. 安装依赖（官方脚本仅需要 curl/tar/xz；其余为 Zen 运行库） ----------
info "安装依赖 ..."
apt update
apt install -y --no-install-recommends \
    curl ca-certificates tar xz-utils \
    libgtk-3-0 libdbus-glib-1-2 libxt6 libnss3 libasound2 \
    fonts-noto-cjk \
    || warn "部分依赖安装失败，继续尝试 ..."
# 注: fonts-noto-cjk 为中文字体(约100MB)，不需要可删除上一行中的该项

# ---------- 3. 以普通用户身份运行官方安装脚本 ----------
[[ -x ${ZEN_INSTALLER} ]] || chmod +x "${ZEN_INSTALLER}"
info "以用户 ${REAL_USER} 身份运行官方安装脚本（gh-proxy 加速下载）..."
info "安装位置: ${REAL_HOME}/.tarball-installations/zen"
sudo -u "${REAL_USER}" bash "${ZEN_INSTALLER}"

info "完成！命令行: ~/.local/bin/zen    菜单: Zen Browser"
warn "若 ~/.local/bin 不在 PATH 中，请将其加入 shell 配置（zsh: export PATH=\"\$HOME/.local/bin:\$PATH\"）"
