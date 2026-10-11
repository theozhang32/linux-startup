# linux-startup

Debian 初次进入环境的批量初始化脚本。所有需要从 GitHub 下载的内容都加了
`https://gh-proxy.com/` 前缀加速；托管在 vercel 等国内访问慢地址的安装脚本
已下载到 `assets/` 本地并完成改写。

## 脚本一览（建议按此顺序执行）

| 脚本 | 作用 | 权限 |
| --- | --- | --- |
| `setup-sudo.sh` | 将用户加入 sudo 组（幂等，可指定用户名） | sudo / root |
| `setup-source.sh` | APT 换清华源（含 debian-security），备份旧配置 | sudo |
| `setup-zsh.sh` | 安装 zsh + 常用插件，设为默认 shell，生成基础 `.zshrc` | sudo |
| `uninstall-firefox-install-zen.sh` | 卸载 firefox-esr，用 Zen 官方安装脚本安装到 `~/.tarball-installations/zen` | sudo |
| `setup-ghostty.sh` | 安装 Ghostty 终端（AppImage 方案），生成 Ghostty 配置 | sudo |
| `setup-starship.sh` | 安装 Starship 提示符，并在 `.zshrc` 追加初始化 | sudo |
| `setup-font.sh` | 安装 JetBrainsMono Nerd Font + 思源黑体 + 思源宋体（均最新版） | sudo |
| `setup-fcitx5-input.sh` | 安装 Fcitx5 + Rime（万象拼音），配置环境并预部署 | sudo |
| `setup-fnm.sh` | 安装 fnm，默认装 Node.js LTS，npm 换国内源 | 普通用户即可 |

```bash
# 系统还没有任何 sudo 用户时：用 root 登录执行
bash setup-sudo.sh <用户名>

# 常规顺序
sudo bash setup-source.sh
sudo bash setup-zsh.sh
sudo bash uninstall-firefox-install-zen.sh
sudo bash setup-ghostty.sh
sudo bash setup-starship.sh
sudo bash setup-font.sh
sudo bash setup-fcitx5-input.sh   # 首次会预编译词库，需几分钟；装完重新登录
bash setup-fnm.sh        # 无需 sudo；装完后重新登录生效
```

## 各脚本说明

### setup-sudo.sh
- 将用户加入 `sudo` 组：`sudo bash setup-sudo.sh`（提升触发者）或指定用户名
- 自动安装缺失的 `sudo` 包；校验 `/etc/sudoers` 的 `%sudo` 规则，缺失则安全补入
- 幂等：已在 sudo 组则跳过；改完需重新登录（或 `newgrp sudo`）生效

### setup-source.sh
- 自动识别 `VERSION_CODENAME`，写入 deb822 格式的 `/etc/apt/sources.list.d/debian.sources`
- `main` `contrib` `non-free` `non-free-firmware` + `updates` + `backports` + `-security` 全部走 `mirrors.tuna.tsinghua.edu.cn`
- 旧 `/etc/apt/sources.list` 会注释禁用（保留备份），`sources.list.d` 下旧 `.sources` 备份后移除
- 换其他镜像：`sudo MIRROR_HOST=mirrors.ustc.edu.cn bash setup-source.sh`

### setup-zsh.sh
- 安装 `zsh` `zsh-autosuggestions` `zsh-syntax-highlighting`
- `chsh` 切换默认 shell 到 zsh（通过 `$SUDO_USER` 定位真实用户）
- 无 `.zshrc` 时生成基础配置（历史、补全、方向键、插件、fnm/starship 预留）

### uninstall-firefox-install-zen.sh
- 精确卸载已安装的 `firefox-esr`（含 i10n 等关联包），未装则跳过
- 安装逻辑直接使用 Zen 官方 install.sh（`assets/zen-install.sh`，仅改写 GitHub 下载地址加 gh-proxy 前缀）
- 官方脚本为用户级安装：`~/.tarball-installations/zen`，命令行 `~/.local/bin/zen`，菜单项 `Zen Browser`
- root 阶段自动安装 curl/tar/xz 及 Zen 运行库，再以 `$SUDO_USER` 身份运行官方脚本
- 附带安装中文字体 `fonts-noto-cjk`（不需要可在脚本里删掉）

### setup-ghostty.sh
- Ghostty 目前 Debian 仓库没有包、官方也只发布 macOS 二进制，这里采用社区
  [pkgforge-dev/ghostty-appimage](https://github.com/pkgforge-dev/ghostty-appimage)
  的 AppImage（自带 GTK4 等全部运行时），解压安装到 `/opt/ghostty`，无需 FUSE
- 生成 `~/.config/ghostty/config`（catppuccin-mocha 主题、内边距等，仅在缺失时创建）
- 备选方案（如需原生 deb）：[mkasberg/ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu)
  的 apt 仓库，或从源码编译

### setup-starship.sh
- Starship 使用本地改写版安装脚本 `assets/starship-install.sh`（原脚本托管在
  starship.rs，国内访问慢，内部下载地址已加 gh-proxy 前缀）
- `.zshrc` 已存在且无相应配置时，追加 `eval "$(starship init zsh)"`

### setup-font.sh
- 三个字体均从 GitHub 最新 release 下载（gh-proxy 优先，直连兕底）：
  - JetBrainsMono Nerd Font：`ryanoasis/nerd-fonts` 的 `JetBrainsMono.zip`，
    装到 `/usr/local/share/fonts/JetBrainsMonoNF`
  - 思源黑体：`adobe-fonts/source-han-sans` 简体中文子集，优先 `CN` 新命名，
    旧 release 无 `CN` 资产时回退 `SC`，装到 `/usr/local/share/fonts/opentype/source-han-sans`
  - 思源宋体：`adobe-fonts/source-han-serif` 同上，装到
    `/usr/local/share/fonts/opentype/source-han-serif`
- 思源与 apt 包 `fonts-noto-cjk`（Noto Sans/Serif CJK）同源，本脚本装的是
  Adobe 官方发布、含全部字重；重复运行会覆盖更新到最新版
- 单个字体安装失败不影响其余字体（最终以非零退出码提示）

### setup-fcitx5-input.sh
- 按[万象拼音官方 Linux 指引](https://amzxyz.github.io/rime-wanxiang/doc/fcitx5-linux)部署：
  apt 装 `fcitx5 fcitx5-rime fcitx5-configtool librime-plugin-lua librime-plugin-octagram`
  等（Lua 扩展与语法模型插件是万象必需）；GTK/Qt 前端模块逐个尽力安装，缺包仅警告
- 环境变量双保险：`/etc/environment` 幂等追加 `GTK_IM_MODULE`/`QT_IM_MODULE`/`XMODIFIERS`，
  并用 `im-config -n fcitx5` 写用户 `~/.xinputrc`（已有其他值不覆盖）
- 万象方案包（`amzxyz/rime-wanxiang` 最新稳定 release 的 `rime-wanxiang-base.zip`）
  与 LTS 语法模型 `wanxiang-lts-zh-hans.gram`（约 380MB，来自 `RIME-LMDG`）下载到
  `~/.local/share/fcitx5/rime`，全程 gh-proxy；模型已存在则跳过
- 用户阶段以目标用户身份执行（runuser），不会在家目录产生 root 属主文件
- 自动生成 fcitx5 profile（键盘-英语 + 中州韵，仅缺失时），`rime_deployer` 预编译词库
- 开机自启动：Debian 的 fcitx5 包不带 `/etc/xdg/autostart` 条目（X11 靠 im-config 的
  Xsession 钩子，Wayland 会话无人拉起），脚本写入用户级
  `~/.config/autostart/org.fcitx.Fcitx5.desktop`，X11/Wayland 均生效（幂等，已有不覆盖）
- 可选变量：`WANXIANG_VARIANT=pure|lite|flypy-fuzhu|...` 选其它发行版；
  `SKIP_GRAM=1` 跳过语法模型；`FORCE=1` 强制重下
- 装完重新登录，Ctrl+Space 切输入法；万象默认全拼，`/flypy` `/zrm` 等斜杠指令切换双拼

### setup-fnm.sh
- fnm 官方安装脚本托管在 fnm.vercel.app（国内访问慢），已下载到
  `assets/fnm-install.sh` 并改写：内部 GitHub 下载地址加了 gh-proxy 前缀
- 安装到 `~/.local/share/fnm`，自动写入 `.zshrc` / `.bashrc`（`--use-on-cd`）
- 默认安装 Node.js **LTS**，下载走 npmmirror 镜像，并把 npm registry 设为
  `https://registry.npmmirror.com`
- 跳过 Node 安装：`INSTALL_NODE_LTS=0 bash setup-fnm.sh`

## assets/ 目录（已下载并改写的第三方脚本）

| 文件 | 原始地址 | 改动 |
| --- | --- | --- |
| `fnm-install.sh` | `https://fnm.vercel.app/install.sh` | 两处 `releases` 下载 URL 加 gh-proxy 前缀 |
| `starship-install.sh` | `https://starship.rs/install.sh` | `BASE_URL` 默认值加 gh-proxy 前缀 |
| `zen-install.sh` | `https://github.com/zen-browser/updates-server/blob/main/install.sh` | release 下载 URL 加 gh-proxy 前缀 |

## gh-proxy 说明

- 脚本内统一通过 `ghp()` 函数给 `github.com` / `raw.githubusercontent.com` /
  `api.github.com` 等直链加 `https://gh-proxy.com/` 前缀
- 下载类操作均为「gh-proxy 优先，直连兜底」
- 日常使用如需克隆仓库，同样可用：
  `git clone https://gh-proxy.com/https://github.com/<user>/<repo>.git`
