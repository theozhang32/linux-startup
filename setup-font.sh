#!/usr/bin/env bash
# ============================================================================
# setup-font.sh — 安装字体（系统级，装入 /usr/local/share/fonts）
#
#   1. JetBrainsMono Nerd Font   — ryanoasis/nerd-fonts 最新 release
#   2. 思源黑体 (Source Han Sans)  — adobe-fonts/source-han-sans 最新 release
#   3. 思源宋体 (Source Han Serif) — adobe-fonts/source-han-serif 最新 release
#
#   思源字体取简体中文子集（新命名 CN，旧版本无 CN 资产时回退 SC）。
#   所有下载走 https://gh-proxy.com/ 前缀（直连兜底）。
#   幂等：重复运行会重新下载并覆盖为最新版本。
#
# 用法: sudo bash setup-font.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
# 注意: info/warn 必须 output 到 stderr —— latest_asset_url 会在 $( ) 命令替换
# 中被调用，若打到 stdout 会连同返回值一起被捕获
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

if [[ ${EUID} -ne 0 ]]; then
    error "请使用 sudo 运行: sudo bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y --no-install-recommends \
    curl ca-certificates unzip fontconfig >/dev/null

# 从 GitHub 最新 release 中按正则挑选下载资产（多个正则依次回退）
latest_asset_url() {
    local repo="$1"; shift
    local api="https://api.github.com/repos/${repo}/releases/latest"
    local json="" url="" re
    info "查询 ${repo} 最新版本（gh-proxy 优先，失败回退直连）..."
    json="$(curl -fsSL --connect-timeout 15 --max-time 30 --retry 2 "$(ghp "${api}")" 2>/dev/null \
         || curl -fsSL --connect-timeout 15 --max-time 30 --retry 2 "${api}" 2>/dev/null || true)"
    if [[ -z ${json} ]]; then
        error "无法获取 ${repo} 的 release 信息"
        return 1
    fi
    for re in "$@"; do
        url="$(printf '%s' "${json}" | grep -o '"browser_download_url": *"[^"]*"' \
               | cut -d '"' -f4 | grep -E "${re}$" | head -n1 || true)"
        [[ -n ${url} ]] && { printf '%s\n' "${url}"; return 0; }
    done
    error "未在 ${repo} 最新 release 中找到匹配的资产: $*"
    return 1
}

# 下载 zip 资产并解压到目标字体目录（先清空旧目录，保证为最新）
install_zip_font() {
    local repo="$1" label="$2" dest="$3"; shift 3
    local url tmp
    url="$(latest_asset_url "${repo}" "$@")" || return 1
    tmp="$(mktemp -d)"
    # 子 shell 位于条件上下文时 bash 会禁用内部的 set -e，
    # 因此逐命令用 || exit 1 显式失败，不依赖 set -e
    if ! (
        cd "${tmp}" || exit 1
        info "${label}: 下载 $(basename "${url}")"
        curl -fL --retry 3 --connect-timeout 20 --max-time 900 -O "$(ghp "${url}")" || exit 1
        unzip -q ./*.zip -d extracted || exit 1
    ); then
        rm -rf "${tmp}"
        return 1
    fi
    rm -rf "${dest}"
    mkdir -p "${dest}"
    cp -a "${tmp}/extracted/." "${dest}/"
    rm -rf "${tmp}"
    info "${label}: 安装到 ${dest}"
}

FAILED=0

install_zip_font ryanoasis/nerd-fonts "JetBrainsMono Nerd Font" \
    /usr/local/share/fonts/JetBrainsMonoNF \
    'JetBrainsMono\.zip' \
    || { error "JetBrainsMono Nerd Font 安装失败"; FAILED=1; }

install_zip_font adobe-fonts/source-han-sans "思源黑体" \
    /usr/local/share/fonts/opentype/source-han-sans \
    'SourceHanSansCN\.zip' 'SourceHanSansSC\.zip' \
    || { error "思源黑体安装失败"; FAILED=1; }

install_zip_font adobe-fonts/source-han-serif "思源宋体" \
    /usr/local/share/fonts/opentype/source-han-serif \
    'SourceHanSerifCN\.zip' 'SourceHanSerifSC\.zip' \
    || { error "思源宋体安装失败"; FAILED=1; }

if [[ ${FAILED} -ne 0 ]]; then
    error "部分字体安装失败，请查看上方日志"
    exit 1
fi

info "刷新字体缓存..."
fc-cache -f >/dev/null

echo
info "已安装的字体族:"
fc-list : family | tr ',' '\n' \
    | grep -iE 'jetbrainsmono.*nerd|source han (sans|serif)|思源(黑体|宋体)' \
    | sed 's/^ *//;s/ *$//' | sort -u

info "完成！字体即装即用，应用程序下次启动即可选择"
