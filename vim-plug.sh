#!/bin/bash
# * =====================================================
# * Copyright © hk. 2022-2026. All rights reserved.
# * File name : vim-plug.sh
# * Author  : 苏木
# * Date    : 2026-11-22
# * Description: 安装 / 卸载 vim-plug（Vim、Neovim 插件管理器），可选写入基础插件配置
# * Reference : https://github.com/junegunn/vim-plug
# * Usage    : ./vim-plug.sh [install|uninstall|status] [--vim] [--nvim] [--with-config] [--mirror] [--purge]
# * ======================================================

# 脚本和工程路径
# ========================================================
SCRIPT_NAME=${0##*/}
SCRIPT_CURRENT_PATH=${0%/*}
SCRIPT_ABSOLUTE_PATH=$(cd "$(dirname "${0}")" >/dev/null 2>&1 && pwd)

# 颜色和日志标识
# ========================================================
# | --- |Black | Red | Green | Yellow | Blue | Magenta | Cyan | White |
# | Fore(Standard) | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 |
# | Fore(light) | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 |
# | Back(Standard) | 40 | 41 | 42 | 43 | 44 | 45 | 46 | 47 |
# | Back(light) | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 |
step() {
    echo -e "\e[96m➤ $@\e[0m"
}
warning() {
    echo -n "⚠️ "
    echo -e "\e[33m$@\e[0m"
}
error() {
    echo -n "❌ "
    echo -e "\e[31m$@\e[0m"
}
success() {
    echo -n "✅ "
    echo -e "\e[32m$@\e[0m"
}
info() {
    echo -ne "\e[32mℹ️ [INFO]\e[0m"
    echo -e "\e[0m$@\e[0m"
}

# 带命令回显的执行函数
# 回显和错误信息输出到 stderr, 不干扰管道和重定向
execute() {
    printf '\e[95m[CMD] %s\e[0m\n' "$*" >&2
    "$@"
    local ret=$?
    if [ ${ret} -ne 0 ]; then
        printf '\e[31m❌ Command failed (exit code: %d): %s\e[0m\n' "${ret}" "$*" >&2
        return ${ret}
    fi
    return 0
}

# ========================================================
# 参数
# ========================================================
# plug.vim 官方下载地址，可通过环境变量 PLUG_URL 覆盖（例如内网镜像）
PLUG_URL_DEFAULT="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

# 公共加速镜像，官方源不可达时按顺序回退
# 用法: https://<mirror>/https://raw.githubusercontent.com/...
PLUG_MIRRORS=(
    "https://ghfast.top/${PLUG_URL_DEFAULT}"
    "https://gh-proxy.com/${PLUG_URL_DEFAULT}"
    "https://ghproxy.net/${PLUG_URL_DEFAULT}"
)

# 安装位置（与 vim-plug 官方 README 一致）
VIM_PLUG_DEST="${HOME}/.vim/autoload/plug.vim"
NVIM_PLUG_DEST="${XDG_DATA_HOME:-${HOME}/.local/share}/nvim/site/autoload/plug.vim"

# 配置文件
VIMRC="${HOME}/.vimrc"
NVIM_INIT="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim/init.vim"
NVIM_INIT_LUA="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim/init.lua"

# 仓库内的配置模板，--with-config 时从此文件读取内容追加到目标配置
# 可用环境变量 VIMRC_TEMPLATE 指向自己的模板
VIMRC_TEMPLATE="${VIMRC_TEMPLATE:-${SCRIPT_ABSOLUTE_PATH}/vimrc}"

# 插件目录
VIM_PLUGGED="${HOME}/.vim/plugged"
NVIM_PLUGGED="${XDG_DATA_HOME:-${HOME}/.local/share}/nvim/plugged"

# 自动写入配置时使用的标记，卸载时按标记整块删除
RC_BEGIN_MARKER="\" >>> vim-plug managed by ${SCRIPT_NAME} >>>"
RC_END_MARKER="\" <<< vim-plug managed by ${SCRIPT_NAME} <<<"

# 选项默认值
ACTION="install"
TARGET_VIM=0
TARGET_NVIM=0
WITH_CONFIG=0
USE_MIRROR=0
PURGE=0

# ========================================================
# 用法说明
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [COMMAND] [OPTIONS]

Commands:
  install        安装 vim-plug（默认命令）
  uninstall      卸载 vim-plug，并移除脚本写入的配置块
  status         查看 plug.vim 与插件目录状态

Options:
  --vim          只处理 Vim
  --nvim         只处理 Neovim
                 （都不指定时，检测到哪个就处理哪个）
  --with-config  把仓库内的 vimrc 模板追加到 ~/.vimrc 或 init.vim（按标记块）
  --mirror       优先使用国内加速镜像下载 plug.vim
  --purge        卸载时一并删除插件目录（~/.vim/plugged 等）
  -h, --help     显示本帮助

Environment:
  PLUG_URL        自定义 plug.vim 下载地址，优先级最高
  VIMRC_TEMPLATE  自定义配置模板路径，默认取脚本同目录下的 vimrc

Examples:
  ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} --nvim --with-config
  ./${SCRIPT_NAME} --mirror
  ./${SCRIPT_NAME} uninstall --purge
EOF
}

# ========================================================
# 依赖检查
check_requirements() {
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        error "neither curl nor wget found, please install one of them first."
        return 1
    fi
    if ! command -v vim &>/dev/null && ! command -v nvim &>/dev/null; then
        error "neither vim nor nvim found, nothing to install for."
        return 1
    fi
    return 0
}

# 未指定 --vim / --nvim 时，按实际存在的编辑器自动选择
detect_targets() {
    if [ ${TARGET_VIM} -eq 0 ] && [ ${TARGET_NVIM} -eq 0 ]; then
        command -v vim &>/dev/null && TARGET_VIM=1
        command -v nvim &>/dev/null && TARGET_NVIM=1
    fi
}

# ========================================================
# 下载 plug.vim
download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl &>/dev/null; then
        execute curl -fsSL --connect-timeout 15 --retry 2 --retry-delay 2 "${url}" -o "${dest}"
    else
        execute wget -q --timeout=15 --tries=2 -O "${dest}" "${url}"
    fi
}

# 校验下载内容：体积和关键函数名都要对得上，避免拿到 HTML 错误页
verify_plug() {
    local file="$1"
    [ -s "${file}" ] || return 1
    local size=$(wc -c < "${file}")
    [ "${size}" -gt 30000 ] || return 1
    grep -q "function! plug#begin" "${file}" || return 1
    grep -q "plug#end" "${file}" || return 1
    return 0
}

# 按候选列表逐个尝试，第一个成功即返回
fetch_plug() {
    local dest="$1"
    local tmp_urls=()
    [ -n "${PLUG_URL}" ] && tmp_urls+=("${PLUG_URL}")
    if [ ${USE_MIRROR} -eq 1 ]; then
        tmp_urls+=("${PLUG_MIRRORS[@]}" "${PLUG_URL_DEFAULT}")
    else
        tmp_urls+=("${PLUG_URL_DEFAULT}" "${PLUG_MIRRORS[@]}")
    fi

    local tmp_file=$(mktemp) || return 1
    local url
    for url in "${tmp_urls[@]}"; do
        step "downloading plug.vim from ${url}"
        if download_file "${url}" "${tmp_file}" && verify_plug "${tmp_file}"; then
            execute mkdir -p "$(dirname "${dest}")" || { rm -f "${tmp_file}"; return 1; }
            if [ -f "${dest}" ]; then
                local backup="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
                execute cp -f "${dest}" "${backup}" || { rm -f "${tmp_file}"; return 1; }
                info "existing plug.vim backed up to ${backup}"
            fi
            execute mv -f "${tmp_file}" "${dest}" || { rm -f "${tmp_file}"; return 1; }
            success "plug.vim installed at ${dest}"
            return 0
        fi
        warning "source unavailable or content invalid, trying next one..."
        : > "${tmp_file}"
    done

    rm -f "${tmp_file}"
    error "failed to download plug.vim from all sources."
    return 1
}

# ========================================================
# 写入基础配置：内容来自仓库内的 vimrc 模板，前后加标记便于卸载
write_config() {
    local rc_file="$1"

    if [ ! -f "${VIMRC_TEMPLATE}" ]; then
        error "config template not found: ${VIMRC_TEMPLATE}"
        info "put a vimrc file next to this script, or set VIMRC_TEMPLATE=/path/to/vimrc"
        return 1
    fi

    # 已由脚本写入过，直接跳过
    if grep -qF "${RC_BEGIN_MARKER}" "${rc_file}" 2>/dev/null; then
        info "managed config block already exists in ${rc_file}, skipping."
        return 0
    fi
    # 用户手动 cp 过模板的场合，避免重复追加一份 plug 声明区
    if grep -qE '^[[:space:]]*call[[:space:]]+plug#begin' "${rc_file}" 2>/dev/null; then
        info "plug#begin() already found in ${rc_file}, skipping to avoid duplicates."
        return 0
    fi

    if [ -f "${rc_file}" ]; then
        local backup="${rc_file}.bak.$(date +%Y%m%d-%H%M%S)"
        execute cp -f "${rc_file}" "${backup}" || return 1
        info "existing config backed up to ${backup}"
    fi

    {
        # 已有内容时先空一行，避免与用户配置粘连
        [ -s "${rc_file}" ] && echo ""
        echo "${RC_BEGIN_MARKER}"
        cat "${VIMRC_TEMPLATE}"
        echo "${RC_END_MARKER}"
    } >> "${rc_file}" || { error "failed to write ${rc_file}"; return 1; }

    success "base config appended to ${rc_file} (from ${VIMRC_TEMPLATE})"
    return 0
}

# 按标记整块移除配置
remove_config() {
    local rc_file="$1"
    [ -f "${rc_file}" ] || return 0
    if ! grep -qF "${RC_BEGIN_MARKER}" "${rc_file}" 2>/dev/null; then
        info "no managed config block in ${rc_file}, skipping."
        return 0
    fi

    local backup="${rc_file}.bak.$(date +%Y%m%d-%H%M%S)"
    execute cp -f "${rc_file}" "${backup}" || return 1

    local tmp_file="${rc_file}.tmp.$$"
    awk -v b="${RC_BEGIN_MARKER}" -v e="${RC_END_MARKER}" '
        $0 == b { skip = 1; next }
        skip && $0 == e { skip = 0; next }
        !skip { print }
    ' "${rc_file}" > "${tmp_file}" && execute mv -f "${tmp_file}" "${rc_file}" || {
        rm -f "${tmp_file}"
        return 1
    }

    # 去掉移除配置块后残留的尾部空行
    if [ -s "${rc_file}" ]; then
        local content=$(cat "${rc_file}")
        printf '%s\n' "${content}" > "${rc_file}"
    fi
    success "managed config block removed from ${rc_file}"
    return 0
}

# ========================================================
# 单个编辑器安装
install_one() {
    local editor="$1"
    local dest="$2"
    local rc_file="$3"

    step "installing vim-plug for ${editor}..."
    fetch_plug "${dest}" || return 1

    if [ ${WITH_CONFIG} -eq 1 ]; then
        if [ "${editor}" = "nvim" ] && [ -f "${NVIM_INIT_LUA}" ]; then
            warning "found ${NVIM_INIT_LUA}, init.vim will be ignored by Neovim."
            warning "please add the plug#begin()/plug#end() block to init.lua manually."
        else
            write_config "${rc_file}" || return 1
        fi
    fi
    return 0
}

# ========================================================
# 安装
do_install() {
    check_requirements || return 1
    detect_targets
    if [ ${TARGET_VIM} -eq 0 ] && [ ${TARGET_NVIM} -eq 0 ]; then
        error "no editor selected, use --vim or --nvim."
        return 1
    fi

    if [ ${TARGET_VIM} -eq 1 ]; then
        if command -v vim &>/dev/null; then
            install_one "vim" "${VIM_PLUG_DEST}" "${VIMRC}" || return 1
        else
            warning "vim not found, skipped."
        fi
    fi

    if [ ${TARGET_NVIM} -eq 1 ]; then
        if command -v nvim &>/dev/null; then
            install_one "nvim" "${NVIM_PLUG_DEST}" "${NVIM_INIT}" || return 1
        else
            warning "nvim not found, skipped."
        fi
    fi

    echo ""
    success "vim-plug installation done."
    info "next step: open vim and run  :PlugInstall"
    info "or run non-interactively:  vim +PlugInstall +qall"
    return 0
}

# ========================================================
# 卸载
do_uninstall() {
    local removed=0

    if [ -f "${VIM_PLUG_DEST}" ]; then
        step "removing ${VIM_PLUG_DEST}"
        execute rm -f "${VIM_PLUG_DEST}" && removed=1
    fi
    if [ -f "${NVIM_PLUG_DEST}" ]; then
        step "removing ${NVIM_PLUG_DEST}"
        execute rm -f "${NVIM_PLUG_DEST}" && removed=1
    fi
    if [ ${removed} -eq 0 ]; then
        warning "plug.vim not found, nothing to remove."
    fi

    remove_config "${VIMRC}" || return 1
    remove_config "${NVIM_INIT}" || return 1

    if [ ${PURGE} -eq 1 ]; then
        local dir
        for dir in "${VIM_PLUGGED}" "${NVIM_PLUGGED}"; do
            if [ -d "${dir}" ]; then
                step "purging plugin directory ${dir}"
                execute rm -rf "${dir}" || return 1
            fi
        done
    else
        info "plugin directories are kept, add --purge to delete them:"
        echo -e "  ${VIM_PLUGGED}"
        echo -e "  ${NVIM_PLUGGED}"
    fi

    success "uninstall done."
    return 0
}

# ========================================================
# 状态
show_status() {
    local name dest dir
    step "vim-plug status"

    echo ""
    echo -e "vim plug.vim : $( [ -f "${VIM_PLUG_DEST}" ] && echo "${VIM_PLUG_DEST} ($(wc -c < "${VIM_PLUG_DEST}") bytes)" || echo "not installed" )"
    echo -e "nvim plug.vim: $( [ -f "${NVIM_PLUG_DEST}" ] && echo "${NVIM_PLUG_DEST} ($(wc -c < "${NVIM_PLUG_DEST}") bytes)" || echo "not installed" )"

    for name in vim nvim; do
        if [ "${name}" = "vim" ]; then
            dir="${VIM_PLUGGED}"
        else
            dir="${NVIM_PLUGGED}"
        fi
        echo ""
        if [ -d "${dir}" ]; then
            echo -e "${name} plugins (${dir}):"
            local count=$(find "${dir}" -mindepth 1 -maxdepth 1 -type d | wc -l)
            find "${dir}" -mindepth 1 -maxdepth 1 -type d -printf '  - %f\n' 2>/dev/null | sort
            echo -e "  total: ${count}, size: $(du -sh "${dir}" 2>/dev/null | cut -f1)"
        else
            echo -e "${name} plugins: directory not found (${dir})"
        fi
    done

    echo ""
    echo -e "vim : $(vim --version 2>/dev/null | head -n 1 || echo 'not found')"
    echo -e "nvim: $(nvim --version 2>/dev/null | head -n 1 || echo 'not found')"
    return 0
}

# ========================================================
# 打印菜单
do_echo_menu() {
    echo "================================================="
    echo -e " vim-plug installer"
    echo "================================================="
    echo -e "action        : ${ACTION}"
    echo -e "target        : vim=${TARGET_VIM} nvim=${TARGET_NVIM}"
    echo -e "with config   : ${WITH_CONFIG}"
    echo -e "use mirror    : ${USE_MIRROR}"
    echo -e "purge         : ${PURGE}"
    echo -e "vim plug.vim  : ${VIM_PLUG_DEST}"
    echo -e "nvim plug.vim : ${NVIM_PLUG_DEST}"
    echo -e "vimrc template: ${VIMRC_TEMPLATE} $( [ -f "${VIMRC_TEMPLATE}" ] && echo "(found)" || echo "(missing)" )"
    echo -e "SCRIPT_ABSOLUTE_PATH : ${SCRIPT_ABSOLUTE_PATH}"
    echo -e "SHELL_PARAM   : ($# total) arg=$*"
    echo ""
    echo "================================================="
}

# ========================================================
# 参数解析
ORIGINAL_ARGS=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        install)        ACTION="install" ;;
        uninstall|remove) ACTION="uninstall" ;;
        status)         ACTION="status" ;;
        --vim)          TARGET_VIM=1 ;;
        --nvim)         TARGET_NVIM=1 ;;
        --with-config)  WITH_CONFIG=1 ;;
        --mirror)       USE_MIRROR=1 ;;
        --purge)        PURGE=1 ;;
        -h|--help)      usage; exit 0 ;;
        *)
            error "unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

do_echo_menu "${ORIGINAL_ARGS[@]}"

case "${ACTION}" in
    install)
        do_install
        ret=$?
        ;;
    uninstall)
        do_uninstall
        ret=$?
        ;;
    status)
        show_status
        ret=$?
        ;;
    *)
        usage
        ret=1
        ;;
esac

exit ${ret}
