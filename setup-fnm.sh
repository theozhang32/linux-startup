#!/usr/bin/env bash
# ============================================================================
# setup-fnm.sh — 安装 fnm (Fast Node Manager)，交互选择并安装 Node.js LTS，
#               再用 npm 全局安装 nrm 并把 npm 镜像切换为 taobao
#
#   fnm 官方安装脚本托管在 fnm.vercel.app（国内访问慢），
#   已下载到 assets/fnm-install.sh，并给脚本内部的 GitHub 下载地址加了
#   gh-proxy 前缀（脚本源码在本地，可自由修改）。
#   Node.js 二进制默认走 npmmirror 镜像 (FNM_NODE_DIST_MIRROR)；
#   远端 LTS 版本列表从镜像站 index.json 检测（需要 curl + jq）。
#
# 用法: bash setup-fnm.sh            # 普通用户运行（推荐，无需 sudo）
#       sudo bash setup-fnm.sh      # 也可以，会自动安装给原用户 (SUDO_USER)
#       sudo bash setup-fnm.sh <用户名>   # root 运行时显式指定目标用户
# 环境变量:
#   INSTALL_NODE_LTS=0              # 跳过 Node.js LTS 安装
#   NODE_LTS_VERSION=<版本号>       # 非交互指定版本（跳过交互菜单，如 v22.23.3 / lts-latest）
#   FNM_NODE_DIST_MIRROR=<url>      # 自定义 Node 发行版镜像
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/assets/fnm-install.sh"
[[ -f ${INSTALLER} ]] || { error "未找到 ${INSTALLER}"; exit 1; }

# 目标用户: root + sudo 场景下安装给原用户（也可显式指定: sudo bash setup-fnm.sh <用户名>）
if [[ ${EUID} -eq 0 ]]; then
    TARGET_USER="${1:-${SUDO_USER:-}}"
    if [[ -z ${TARGET_USER} || ${TARGET_USER} == "root" ]]; then
        error "未能确定目标用户；请在普通用户下运行，或用 sudo 并显式指定: sudo bash $0 <用户名>"
        exit 1
    fi
else
    TARGET_USER="$(id -un)"
fi
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
FNM_DIR="${TARGET_HOME}/.local/share/fnm"
[[ -d "${TARGET_HOME}/.fnm" ]] && FNM_DIR="${TARGET_HOME}/.fnm"   # 兼容旧版默认目录

# ---------- 1. 系统依赖 ----------
MISSING=()
command -v curl  >/dev/null 2>&1 || MISSING+=(curl)
command -v unzip >/dev/null 2>&1 || MISSING+=(unzip)
command -v jq    >/dev/null 2>&1 || MISSING+=(jq)
# root 运行时 run_as_user 需要 sudo -u 切换到目标用户（最小化系统可能未装）
if [[ ${EUID} -eq 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    MISSING+=(sudo)
fi
if ((${#MISSING[@]} > 0)); then
    info "安装缺失依赖: ${MISSING[*]}"
    if [[ ${EUID} -eq 0 ]]; then
        apt update && apt install -y "${MISSING[@]}"
    elif command -v sudo >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y "${MISSING[@]}"
    else
        error "缺少 ${MISSING[*]}，请手动安装后重试"
        exit 1
    fi
fi

# 以目标用户身份执行（保证装到用户目录而不是 /root）
run_as_user() {
    if [[ ${EUID} -eq 0 && ${TARGET_USER} != "root" ]]; then
        sudo -u "${TARGET_USER}" -H env HOME="${TARGET_HOME}" "$@"
    else
        "$@"
    fi
}

# ---------- 2. 运行本地改写版安装脚本 ----------
# shell 配置由本脚本统一写入，因此传 --skip-shell 避免重复追加
info "安装 fnm 到 ${FNM_DIR}（本地改写版脚本，GitHub 下载走 gh-proxy）..."
run_as_user bash "${INSTALLER}" --install-dir "${FNM_DIR}" --skip-shell
[[ -x "${FNM_DIR}/fnm" ]] || { error "fnm 安装失败"; exit 1; }
info "fnm 已安装: ${FNM_DIR}/fnm ($("${FNM_DIR}/fnm" --version 2>/dev/null || echo '?'))"

# ---------- 3. 写入 shell 配置 ----------
FNM_REL="${FNM_DIR#"$TARGET_HOME"/}"   # 例: .local/share/fnm
add_fnm_rc() {
    local rc="$1" shell_name="$2"
    if grep -qF 'fnm env' "${rc}" 2>/dev/null; then
        info "${rc} 已包含 fnm 配置，跳过"
        return 0
    fi
    cat >> "${rc}" <<EOF

# fnm (Fast Node Manager)
FNM_PATH="\$HOME/${FNM_REL}"
if [ -d "\$FNM_PATH" ]; then
    export PATH="\$FNM_PATH:\$PATH"
    eval "\$(fnm env --use-on-cd --shell ${shell_name})"
fi
EOF
    chown "${TARGET_USER}:" "${rc}" 2>/dev/null || true
    info "已写入 ${rc}"
}
command -v zsh >/dev/null 2>&1 && add_fnm_rc "${TARGET_HOME}/.zshrc" zsh
[[ -f "${TARGET_HOME}/.bashrc" ]] && add_fnm_rc "${TARGET_HOME}/.bashrc" bash

# ---------- 4. 安装 Node.js LTS（默认执行，INSTALL_NODE_LTS=0 可跳过） ----------
if [[ "${INSTALL_NODE_LTS:-1}" = "1" ]]; then
    export FNM_NODE_DIST_MIRROR="${FNM_NODE_DIST_MIRROR:-https://npmmirror.com/mirrors/node}"

    # 4.1 检测远端所有 LTS 版本
    #     index.json 含全部历史版本，lts 字段为 LTS 代号（非 LTS 为 false）；
    #     每条 LTS 线（argon/boron/...）只展示其最新版本，避免菜单过长
    info "检测远端 LTS 版本列表（${FNM_NODE_DIST_MIRROR%/}/index.json）..."
    mapfile -t LTS_LINES < <(curl -fsSL --connect-timeout 15 \
            "${FNM_NODE_DIST_MIRROR%/}/index.json" | jq -r '
        [.[] | select(.lts != false and .lts != null)]
        | group_by(.lts)
        | map(max_by(.date))
        | sort_by(.version | sub("^v";"") | split(".") | map(tonumber)) | reverse
        | .[] | [.version, (.lts | ascii_downcase), .date] | @tsv')

    # 4.2 选择要安装的版本
    if [[ -n "${NODE_LTS_VERSION:-}" ]]; then
        CHOICE="${NODE_LTS_VERSION}"          # 非交互：环境变量直接指定
        info "NODE_LTS_VERSION=${CHOICE}，跳过交互选择"
    elif (( ${#LTS_LINES[@]} == 0 )); then
        warn "未能获取远端版本列表，回退到 lts-latest"
        CHOICE="lts-latest"
    elif [[ ! -t 0 ]]; then
        warn "非交互终端（stdin 不是 tty），默认安装最新 LTS"
        IFS=$'\t' read -r CHOICE _ <<<"${LTS_LINES[0]}"
    else
        echo "远端可用 LTS 版本（各 LTS 线最新版，从新到旧）："
        for i in "${!LTS_LINES[@]}"; do
            IFS=$'\t' read -r VER CODENAME DATE <<<"${LTS_LINES[$i]}"
            printf '  %2d) %-12s (%-10s 发布于 %s)\n' "$((i+1))" "${VER}" "${CODENAME}" "${DATE}"
        done
        while true; do
            printf '选择要安装的 LTS 版本 [1]：'
            read -r ANSWER || ANSWER=1    # EOF/Ctrl-D → 默认第 1 项
            ANSWER="${ANSWER:-1}"         # 直接回车 → 默认第 1 项（最新 LTS）
            if [[ "${ANSWER}" =~ ^[0-9]+$ ]] && (( ANSWER >= 1 && ANSWER <= ${#LTS_LINES[@]} )); then
                IFS=$'\t' read -r CHOICE _ <<<"${LTS_LINES[$((ANSWER-1))]}"
                break
            fi
            if [[ "${ANSWER}" =~ ^v?[0-9]+(\.[0-9]+){2}$ ]]; then
                CHOICE="v${ANSWER#v}"     # 也允许直接输入完整版本号
                break
            fi
            warn "无效输入: ${ANSWER}（输入序号或完整版本号，如 v22.23.3）"
        done
    fi
    info "将安装 Node.js: ${CHOICE}（镜像: ${FNM_NODE_DIST_MIRROR}）"

    # 4.3 安装并设为 default
    if [[ "${CHOICE}" == "lts-latest" ]]; then
        if ! run_as_user env FNM_NODE_DIST_MIRROR="${FNM_NODE_DIST_MIRROR}" \
                "${FNM_DIR}/fnm" install --lts; then
            warn "--lts 失败，尝试 lts-latest 别名 ..."
            run_as_user env FNM_NODE_DIST_MIRROR="${FNM_NODE_DIST_MIRROR}" \
                "${FNM_DIR}/fnm" install lts-latest
        fi
    else
        run_as_user env FNM_NODE_DIST_MIRROR="${FNM_NODE_DIST_MIRROR}" \
            "${FNM_DIR}/fnm" install "${CHOICE}"
    fi
    run_as_user "${FNM_DIR}/fnm" default "${CHOICE}" \
        || warn "设置默认版本失败，可稍后手动执行: fnm default ${CHOICE}"

    # 4.4 npm 全局安装 nrm，并把 npm 镜像切换为 taobao
    #     优先用 default 别名下的 npm（fnm default 失败时回退到遍历查找）
    NODE_BIN_DIR="${FNM_DIR}/aliases/default/bin"
    if [[ ! -x "${NODE_BIN_DIR}/npm" ]]; then
        shopt -s nullglob
        for npm_bin in "${FNM_DIR}"/node-versions/*/installation/bin/npm; do
            [[ -x ${npm_bin} ]] && NODE_BIN_DIR="$(dirname "${npm_bin}")" && break
        done
        shopt -u nullglob
    fi

    if [[ -x "${NODE_BIN_DIR}/npm" ]]; then
        info "npm 全局安装 nrm（走 npmmirror 镜像）..."
        # npm/nrm 的可执行文件都是 #!/usr/bin/env node，
        # 因此所有调用都要把 node bin 目录放进 PATH
        if run_as_user env HOME="${TARGET_HOME}" PATH="${NODE_BIN_DIR}:${PATH}" \
                "${NODE_BIN_DIR}/npm" install -g nrm --registry=https://registry.npmmirror.com \
           && run_as_user env HOME="${TARGET_HOME}" PATH="${NODE_BIN_DIR}:${PATH}" \
                "${NODE_BIN_DIR}/nrm" use taobao; then
            info "npm 镜像已通过 nrm 切换为 taobao (https://registry.npmmirror.com)"
        else
            warn "nrm 安装/切换失败，直接设置 npm registry"
            run_as_user env HOME="${TARGET_HOME}" PATH="${NODE_BIN_DIR}:${PATH}" \
                "${NODE_BIN_DIR}/npm" config set registry https://registry.npmmirror.com \
                || warn "npm registry 设置失败"
        fi
    else
        warn "未找到 npm 可执行文件，跳过 nrm 安装"
    fi
fi

info "完成！重新打开终端（或重新登录）后: node -v / npm -v"
info "常用命令: fnm ls  |  fnm install --lts  |  fnm use <版本>  |  fnm default <版本>"
info "npm 镜像: nrm ls 查看全部  |  nrm use taobao 切换"
