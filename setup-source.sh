#!/usr/bin/env bash
# ============================================================================
# setup-source.sh — 将 Debian 的 apt 源切换为清华大学 TUNA 镜像
#   包含 debian-security 安全更新源（同样换成清华源），deb822 格式
# 用法: sudo bash setup-source.sh
# 可选环境变量:
#   MIRROR_HOST=mirrors.tuna.tsinghua.edu.cn   # 换成其他镜像站主机名
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

if [[ ! -f /etc/debian_version ]]; then
    error "未检测到 /etc/debian_version，本脚本仅支持 Debian"
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${VERSION_CODENAME:-}"
if [[ -z ${CODENAME} ]]; then
    error "无法从 /etc/os-release 获取版本代号 (VERSION_CODENAME)，请手动确认发行版版本"
    exit 1
fi

MIRROR_HOST="${MIRROR_HOST:-mirrors.tuna.tsinghua.edu.cn}"
BASE_URL="https://${MIRROR_HOST}/debian"
SECURITY_URL="https://${MIRROR_HOST}/debian-security"
TS="$(date +%Y%m%d-%H%M%S)"

info "检测到 Debian ${CODENAME}，使用镜像: ${MIRROR_HOST}"

# ---------- 1. 备份并禁用旧的单文件源 ----------
if [[ -f /etc/apt/sources.list ]]; then
    cp -a /etc/apt/sources.list "/etc/apt/sources.list.bak.${TS}"
    # 注释掉所有未注释的行（保留文件本身，部分工具依赖其存在；幂等）
    sed -i 's/^[[:space:]]*\([^#[:space:]]\)/# \1/' /etc/apt/sources.list
    info "已备份并禁用 /etc/apt/sources.list (备份: sources.list.bak.${TS})"
fi

# ---------- 2. 备份并清理 sources.list.d 下已有的 .sources，避免残留其他镜像 ----------
mkdir -p /etc/apt/sources.list.d
shopt -s nullglob
for f in /etc/apt/sources.list.d/*.sources; do
    cp -a "$f" "${f}.bak.${TS}"
    rm -f "$f"
    info "已备份并移除 $f"
done
shopt -u nullglob

# ---------- 3. 写入清华源（deb822 格式，bookworm 及以后版本支持） ----------
cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: ${BASE_URL}
Suites: ${CODENAME} ${CODENAME}-updates ${CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: ${SECURITY_URL}
Suites: ${CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
info "已写入 /etc/apt/sources.list.d/debian.sources"

# ---------- 4. 刷新索引 ----------
info "apt update ..."
apt update

info "完成！当前生效的源:"
grep '^URIs' /etc/apt/sources.list.d/debian.sources | sed 's/^/    /'
