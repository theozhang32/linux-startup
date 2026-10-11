#!/usr/bin/env bash
# ============================================================================
# setup-fcitx5-input.sh — 安装 Fcitx5 中文输入法（Rime + 万象拼音）
#
#   1. apt 安装 fcitx5 / fcitx5-rime 及 librime 的 lua、octagram 插件
#      （万象依赖 Lua 扩展与语法模型插件，官方指引要求的包）
#   2. 配置输入法环境变量（/etc/environment + im-config 设为 fcitx5）
#   3. 下载万象拼音方案包（默认 Base 版）与 LTS 语法模型到
#      ~/.local/share/fcitx5/rime（全部走 gh-proxy 前缀）
#   4. 预生成 fcitx5 profile（默认启用「键盘-英语」+「中州韵」）
#   5. 用 rime_deployer 预编译词库（首次部署耗时较长）
#
# 用法: sudo bash setup-fcitx5-input.sh [用户名]
#   完成后注销重新登录生效。
#
# 可选环境变量:
#   WANXIANG_VARIANT=base|pure|lite|flypy-fuzhu|zrm-fuzhu|...  万象发行版（默认 base）
#   SKIP_GRAM=1    跳过 ~380MB 语法模型下载（只装方案，无整句预测）
#   FORCE=1        强制重新下载方案与模型（默认已存在则跳过）
#
#   万象默认全拼；输入状态下可用斜杠指令切换:
#   /flypy 小鹤双拼  /zrm 自然码  /pinyin 全拼 ...（详见万象文档）
#   https://amzxyz.github.io/rime-wanxiang/doc/fcitx5-linux
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
# 注意: info/warn 输出到 stderr，避免被 $( ) 命令替换捕获污染返回值
info() { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
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

VARIANT="${WANXIANG_VARIANT:-base}"
SKIP_GRAM="${SKIP_GRAM:-0}"
FORCE="${FORCE:-0}"

export DEBIAN_FRONTEND=noninteractive
apt update

# ---------- 1. apt 包 ----------
# 核心（官方 fcitx5-linux 指引要求的包 + 配置工具）
apt install -y --no-install-recommends \
    fcitx5 fcitx5-rime fcitx5-configtool \
    librime1 librime-bin librime-plugin-lua librime-plugin-octagram \
    im-config curl ca-certificates unzip >/dev/null

# 各图形前端 IM 模块：发行版间包名有差异，逐个尽力安装
for fe in fcitx5-frontend-gtk2 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 \
          fcitx5-frontend-qt5 fcitx5-frontend-qt6; do
    apt install -y --no-install-recommends "${fe}" >/dev/null 2>&1 \
        || warn "未安装 ${fe}（当前仓库无此包，可忽略）"
done
info "fcitx5 及 Rime 依赖安装完成"

# ---------- 2. 环境变量 ----------
ensure_env() {
    local key="$1" val="$2"
    if grep -qE "^${key}=" /etc/environment 2>/dev/null; then
        if ! grep -qE "^${key}=${val}$" /etc/environment; then
            warn "/etc/environment 中 ${key} 已有其他值，保持不变"
        fi
        return 0
    fi
    printf '%s=%s\n' "${key}" "${val}" >> /etc/environment
    info "已写入 /etc/environment: ${key}=${val}"
}
ensure_env GTK_IM_MODULE fcitx
ensure_env QT_IM_MODULE fcitx
ensure_env XMODIFIERS '@im=fcitx'

# im-config 设 fcitx5 为用户默认输入法框架（写 ~/.xinputrc）
runuser -u "${TARGET_USER}" -- im-config -n fcitx5 2>/dev/null \
    && info "im-config 已设为 fcitx5" \
    || warn "im-config 设置失败（不影响 /etc/environment 方式）"

# ---------- 3+4+5. 用户阶段：下载方案/模型、profile、预部署 ----------
# 以目标用户身份运行，避免家目录出现 root 属主文件
if ! runuser -u "${TARGET_USER}" -- bash -s -- \
        "${SCRIPT_DIR}" "${VARIANT}" "${SKIP_GRAM}" "${FORCE}" <<'USER_PHASE'
set -euo pipefail
c_green='\033[0;32m'; c_nc='\033[0m'
uinfo() { echo -e "${c_green}[INFO]${c_nc} $*" >&2; }

GH_PROXY="https://gh-proxy.com/"
ghp() {
    case "$1" in
        https://github.com/*|https://raw.githubusercontent.com/*|\
        https://api.github.com/*|https://objects.githubusercontent.com/*)
            echo "${GH_PROXY}$1" ;;
        *) echo "$1" ;;
    esac
}

SCRIPT_DIR="$1"; VARIANT="$2"; SKIP_GRAM="$3"; FORCE="$4"
RIME_DIR="${HOME}/.local/share/fcitx5/rime"
mkdir -p "${RIME_DIR}"

# --- 语法模型（LTS 固定 tag，~380MB） ---
GRAM="${RIME_DIR}/wanxiang-lts-zh-hans.gram"
if [[ ${SKIP_GRAM} == 1 ]]; then
    uinfo "SKIP_GRAM=1，跳过语法模型"
elif [[ -s ${GRAM} && ${FORCE} != 1 ]]; then
    uinfo "语法模型已存在，跳过（FORCE=1 可强制重新下载）"
else
    url="https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
    uinfo "下载语法模型（约 380MB，走 gh-proxy，请耐心等待）..."
    curl -fL --retry 3 --connect-timeout 20 --max-time 3600 -o "${GRAM}.tmp" "$(ghp "${url}")"
    mv "${GRAM}.tmp" "${GRAM}"
fi

# --- 万象方案包（最新稳定 release 的 rime-wanxiang-<variant>.zip） ---
api="https://api.github.com/repos/amzxyz/rime-wanxiang/releases/latest"
uinfo "查询万象拼音最新版本（gh-proxy 优先，失败回退直连）..."
json="$(curl -fsSL --connect-timeout 15 --max-time 30 --retry 2 "$(ghp "${api}")" 2>/dev/null \
     || curl -fsSL --connect-timeout 15 --max-time 30 --retry 2 "${api}" 2>/dev/null || true)"
if [[ -z ${json} ]]; then
    echo "无法获取 amzxyz/rime-wanxiang 的 release 信息" >&2; exit 1
fi
url="$(printf '%s' "${json}" | grep -o '"browser_download_url": *"[^"]*"' \
       | cut -d '"' -f4 | grep -E "rime-wanxiang-${VARIANT}\.zip$" | head -n1 || true)"
if [[ -z ${url} ]]; then
    echo "最新 release 中未找到 rime-wanxiang-${VARIANT}.zip（检查 WANXIANG_VARIANT 拼写）" >&2; exit 1
fi

tmp="$(mktemp -d)"
if ! (
    cd "${tmp}" || exit 1
    uinfo "下载方案包: $(basename "${url}")"
    curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -O "$(ghp "${url}")" || exit 1
    unzip -q ./*.zip -d extracted || exit 1
); then rm -rf "${tmp}"; echo "方案包下载/解压失败" >&2; exit 1; fi

# 方案文件直接并入用户 Rime 目录（覆盖旧版；文档要求不保留外层目录）
rm -rf "${RIME_DIR}/build"
cp -a "${tmp}/extracted/." "${RIME_DIR}/"
rm -rf "${tmp}"
uinfo "方案文件已安装到 ${RIME_DIR}"

# --- fcitx5 profile：默认启用「键盘-英语」+「中州韵」（仅缺失时生成） ---
FCITX5_CONF="${HOME}/.config/fcitx5"
if [[ ! -f "${FCITX5_CONF}/profile" ]]; then
    mkdir -p "${FCITX5_CONF}"
    cat > "${FCITX5_CONF}/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=rime
Layout=

[Group Order]
0=Default
EOF
    uinfo "已生成 fcitx5 profile（键盘-英语 + 中州韵）"
else
    uinfo "已存在 fcitx5 profile，保持不变（如未添加中州韵请在配置工具中添加）"
fi

# --- 开机自启动 ---
# Debian 的 fcitx5 包不带 /etc/xdg/autostart 条目：X11 靠 im-config 的 Xsession
# 钩子拉起，Wayland 会话则无人启动 → 用户级 XDG 自启动补齐（两种会话都生效）
AUTOSTART="${HOME}/.config/autostart"
if [[ -f /etc/xdg/autostart/org.fcitx.Fcitx5.desktop ]]; then
    uinfo "系统已提供 /etc/xdg/autostart 自启动条目，无需用户级配置"
elif [[ ! -f "${AUTOSTART}/org.fcitx.Fcitx5.desktop" ]]; then
    mkdir -p "${AUTOSTART}"
    cat > "${AUTOSTART}/org.fcitx.Fcitx5.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx 5
Exec=fcitx5
Icon=fcitx
Terminal=false
Categories=System;Utility;
X-GNOME-Autostart-enabled=true
EOF
    uinfo "已创建用户级开机自启动: ${AUTOSTART}/org.fcitx.Fcitx5.desktop"
else
    uinfo "用户级自启动已存在，保持不变"
fi
USER_PHASE
then
    error "用户阶段执行失败（下载/配置），请查看上方日志"
    exit 1
fi

# ---------- 预编译词库（best-effort） ----------
if command -v rime_deployer >/dev/null 2>&1; then
    info "预编译词库（首次部署耗时较长，请耐心等待）..."
    if ! runuser -u "${TARGET_USER}" -- rime_deployer --build \
            "${TARGET_HOME}/.local/share/fcitx5/rime" /usr/share/rime-data 2>/dev/null; then
        warn "预编译失败，不影响安装；登录后在 fcitx5 托盘菜单选「重新部署」即可"
    fi
else
    warn "未找到 rime_deployer，跳过预编译；登录后在 fcitx5 托盘菜单选「重新部署」"
fi

info "完成！注销重新登录后按 Ctrl+Space 切换输入法"
info "万象默认全拼；/flypy 小鹤双拼、/zrm 自然码等斜杠指令可切换输入方案"
