#!/usr/bin/env bash
# ============================================================================
# setup-ghostty.sh — 安装 Ghostty 终端
#
#   Debian 官方仓库暂无 ghostty 包，官方也只发布 macOS 预编译包；
#   这里采用社区 AppImage (pkgforge-dev/ghostty-appimage)，
#   自带 GTK4 等全部运行时，解压后直接运行（不需要 FUSE），
#   下载全程走 https://gh-proxy.com/ 前缀。
#   （若你的 apt 仓库已有 ghostty，脚本会优先用 apt 安装）
#
#   Starship 提示符已拆分到 setup-starship.sh。
#
# 用法: sudo bash setup-ghostty.sh [用户名]
#   配置文件写入目标用户家目录；未指定时用 $SUDO_USER，root 直接运行须指定
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

GH_PROXY="https://gh-proxy.com/"
ghp() {
    local url="$1"
    case "${url}" in
        https://github.com/*|https://raw.githubusercontent.com/*|\
        https://api.github.com/*|https://objects.githubusercontent.com/*)
            echo "${GH_PROXY}${url}" ;;
        *) echo "${url}" ;;
    esac
}

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
# 也可显式指定用户: sudo bash setup-ghostty.sh <用户名>
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

export DEBIAN_FRONTEND=noninteractive
apt update

# ---------- 1. Ghostty ----------
install_ghostty() {
    # 优先: 发行版仓库已收录 ghostty（如未来的 Debian / Ubuntu 26.04+）
    if apt install -y -qq --no-install-recommends ghostty 2>/dev/null; then
        info "已通过 apt 安装 ghostty"
        return 0
    fi
    info "apt 仓库无 ghostty，改用 AppImage 方案（gh-proxy 加速）..."

    apt install -y --no-install-recommends \
        curl ca-certificates tar desktop-file-utils shared-mime-info >/dev/null

    local arch
    case "$(dpkg --print-architecture)" in
        amd64) arch="x86_64" ;;
        arm64) arch="aarch64" ;;
        *) error "不支持的架构: $(dpkg --print-architecture)"; return 1 ;;
    esac

    local api="https://api.github.com/repos/pkgforge-dev/ghostty-appimage/releases/latest"
    local json="" url=""
    info "查询 Ghostty AppImage 最新版本（gh-proxy 优先，失败回退直连）..."
    json="$(curl -fsSL --connect-timeout 15 --retry 2 "$(ghp "${api}")" 2>/dev/null \
         || curl -fsSL --connect-timeout 15 --retry 2 "${api}" 2>/dev/null || true)"
    if [[ -n ${json} ]]; then
        url="$(printf '%s' "${json}" | grep -o '"browser_download_url": *"[^"]*"' \
               | cut -d '"' -f4 | grep -E "/Ghostty-[0-9][0-9.]*-${arch}\.AppImage$" \
               | head -n1 || true)"
    fi
    if [[ -z ${url} ]]; then
        error "未找到匹配 ${arch} 的 Ghostty AppImage 资产"
        return 1
    fi

    local tmp
    tmp="$(mktemp -d)"
    (   # 子 shell，结束后自动清理临时目录
        set -e
        cd "${tmp}"
        info "下载: $(ghp "${url}")"
        curl -fL --retry 3 --connect-timeout 20 -O "$(ghp "${url}")"
        chmod +x ./*.AppImage

        info "解压 AppImage（免 FUSE，直接解出运行时）..."
        ./*.AppImage --appimage-extract >/dev/null
        [[ -d squashfs-root ]] || { echo "AppImage 解压失败" >&2; exit 1; }
        sudo rm -rf /opt/ghostty 2>/dev/null || rm -rf /opt/ghostty
        mkdir -p /opt/ghostty
        cp -a squashfs-root/. /opt/ghostty/
    ) || { rm -rf "${tmp}"; return 1; }
    rm -rf "${tmp}"

    # 启动包装脚本
    cat > /usr/local/bin/ghostty <<'EOF'
#!/bin/sh
exec /opt/ghostty/AppRun "$@"
EOF
    chmod +x /usr/local/bin/ghostty

    # 菜单项与图标
    ICON="$(find /opt/ghostty -maxdepth 3 -name '*.png' 2>/dev/null | head -n1 || true)"
    [[ -z ${ICON} ]] && ICON="utilities-terminal"
    mkdir -p /usr/local/share/applications
    cat > /usr/local/share/applications/ghostty.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=Ghostty
GenericName=Terminal
Comment=A fast, feature-rich terminal
Exec=/usr/local/bin/ghostty
Icon=${ICON}
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
StartupWMClass=com.mitchellh.ghostty
EOF
    update-desktop-database /usr/local/share/applications 2>/dev/null || true
    info "Ghostty 安装完成: /usr/local/bin/ghostty"
    return 0
}

install_ghostty || error "Ghostty 安装失败（备选方案见 README.md：mkasberg/ghostty-ubuntu 的 deb 仓库，或源码编译）"

# ---------- 2. 配置文件 ----------
# Ghostty 配置（仅当不存在时创建；Ghostty 内置 Nerd Font，提示符图标可直接显示）
GCONF_DIR="${TARGET_HOME}/.config/ghostty"
if [[ ! -f "${GCONF_DIR}/config" ]]; then
    mkdir -p "${GCONF_DIR}"
    cat > "${GCONF_DIR}/config" <<'EOF'
# Ghostty 配置参考: https://ghostty.org/docs/config
theme = catppuccin-mocha
font-size = 14
window-padding-x = 8
window-padding-y = 8
EOF
    chown -R "${TARGET_USER}:" "${GCONF_DIR}"
    info "已生成 ${GCONF_DIR}/config"
else
    info "已存在 ${GCONF_DIR}/config，保持不变"
fi

info "完成！终端: ghostty（Starship 提示符请运行 setup-starship.sh）"
