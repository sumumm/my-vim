#!/bin/bash
# =====================================================
# Copyright © hk. 2022-2026. All rights reserved.
# File name : sync-plugins.sh
# Author  : 苏木
# Date    : 2026-11-22
# Description: 按 pack/plugins.tsv 同步内置组件到上游最新提交，
#              回写清单、刷新 README，并在 CI 中自动提交推送
# Usage   : scripts/sync-plugins.sh [--dry-run] [--no-push]
#   --dry-run  只检查差异，不修改工作区
#   --no-push  同步并提交，但不推送
# Environment:
#   DRY_RUN_INPUT=true  同 --dry-run（供页面按钮传入）
#   BRANCH=<分支>       推送目标分支，默认取 CNB_BRANCH 或 main
# =====================================================

set -o pipefail

SCRIPT_NAME=${0##*/}
REPO_ROOT=$(cd "$(dirname "${0}")/.." >/dev/null 2>&1 && pwd)
MANIFEST="${REPO_ROOT}/pack/plugins.tsv"
README="${REPO_ROOT}/README.md"
BRANCH=${BRANCH:-${CNB_BRANCH:-main}}

DRY_RUN=0
PUSH=1
WORK=""
CHANGES=()

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
die() {
    error "$@"
    exit 1
}

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  --dry-run  只检查上游是否有更新，不修改工作区
  --no-push  同步并提交，但不推送
  -h, --help 显示本帮助

Environment:
  DRY_RUN_INPUT=true  同 --dry-run（页面按钮传参）
  BRANCH=<分支>       推送目标分支，默认 \${CNB_BRANCH} 或 main
EOF
}

parse_args() {
    case "${DRY_RUN_INPUT:-}" in
        1|true|TRUE|yes|是) DRY_RUN=1 ;;
    esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --no-push) PUSH=0 ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown argument: $1 (available: --dry-run / --no-push)" ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------- 同步动作
# 目录目标：用 git archive 生成一份完整树，再整体替换，保证与上游无差异
sync_directory() {
    local up_repo="$1"
    local dst="$2"
    local name
    name=$(basename "${dst}")
    local stage="${WORK}/stage-${name}"

    mkdir -p "${stage}" || return 1
    git -C "${up_repo}" archive HEAD | tar -x -C "${stage}" || return 1

    if [ -d "${dst}" ]; then
        mv "${dst}" "${WORK}/old-${name}" || return 1
    fi
    mkdir -p "$(dirname "${dst}")" || return 1
    mv "${stage}" "${dst}" || return 1
    return 0
}

# 文件目标：只替换上游同名文件
sync_file() {
    local up_repo="$1"
    local dst="$2"
    local base
    base=$(basename "${dst}")

    if [ ! -f "${up_repo}/${base}" ]; then
        error "upstream file not found: ${up_repo}/${base}"
        return 1
    fi
    mkdir -p "$(dirname "${dst}")" || return 1
    cp -f "${up_repo}/${base}" "${dst}" || return 1
    return 0
}

# 判断本地与上游是否已有内容差异（hash 相同但内容被改过时用于纠正）
content_differs() {
    local up_repo="$1"
    local dst="$2"

    if [ -d "${dst}" ]; then
        ! diff -r --exclude=.git --exclude=tags "${dst}" "${up_repo}" >/dev/null 2>&1
        return
    fi
    ! cmp -s "${dst}" "${up_repo}/$(basename "${dst}")"
}

# ---------------------------------------------------------------- 清单回写
update_manifest_row() {
    local name="$1"
    local commit="$2"
    local date="$3"
    local tmp
    tmp=$(mktemp) || return 1

    awk -F'\t' -v OFS='\t' -v n="${name}" -v c="${commit}" -v d="${date}" '
        /^#/ { print; next }
        NF >= 6 && $1 == n { $4 = c; $5 = d }
        { print }
    ' "${MANIFEST}" > "${tmp}" && cp -f "${tmp}" "${MANIFEST}"
    local ret=$?
    rm -f "${tmp}"
    return ${ret}
}

# ---------------------------------------------------------------- 提交推送
stage_and_commit() {
    git add -A -- pack vendor README.md || return 1
    if git diff --cached --quiet; then
        info "no changes to commit."
        return 1
    fi

    # CNB 的提交签名要求作者与令牌用户一致
    local author_name=${GIT_AUTHOR_NAME:-${CNB_BUILD_USER:-}}
    local author_email=${GIT_AUTHOR_EMAIL:-${CNB_BUILD_USER_EMAIL:-}}
    local -a git_cmd=(git)
    [ -n "${author_name}" ] && git_cmd+=(-c "user.name=${author_name}")
    [ -n "${author_email}" ] && git_cmd+=(-c "user.email=${author_email}")

    local body
    body=$(printf '%s\n' "${CHANGES[@]}")
    if ! "${git_cmd[@]}" commit --quiet -m "ci(plugins): 同步内置组件到上游最新" -m "${body}"; then
        warning "commit with signature failed, retry with --no-gpg-sign"
        "${git_cmd[@]}" commit --quiet --no-gpg-sign -m "ci(plugins): 同步内置组件到上游最新" -m "${body}" || return 1
    fi
    success "committed: $(git log -1 --format='%h %s')"
    return 0
}

resolve_push_url() {
    if [ -n "${CNB_TOKEN:-}" ]; then
        local base=${CNB_REPO_URL_HTTPS:-https://${CNB_WEB_HOST:-cnb.cool}/${CNB_REPO_SLUG:-}}
        [ -n "${base}" ] || return 1
        printf 'https://cnb:%s@%s\n' "${CNB_TOKEN}" "${base#https://}"
        return 0
    fi
    info "CNB_TOKEN not found, fallback to origin (need local push permission)" >&2
    git remote get-url origin
}

push_changes() {
    local url
    url=$(resolve_push_url) || { error "cannot resolve push url"; return 1; }

    if ! git push --quiet "${url}" "HEAD:refs/heads/${BRANCH}" 2> "${WORK}/push.err"; then
        sed "s|${CNB_TOKEN:-__none__}|***|g" "${WORK}/push.err" >&2
        error "push to ${BRANCH} failed (branch protection or non-fast-forward)"
        return 1
    fi
    success "pushed to ${BRANCH}"
    return 0
}

# ---------------------------------------------------------------- 主流程
main() {
    parse_args "$@"

    [ -f "${MANIFEST}" ] || die "manifest not found: ${MANIFEST}"
    command -v git &>/dev/null || die "git not found"
    command -v tar &>/dev/null || die "tar not found"

    WORK=$(mktemp -d) || die "cannot create temp dir"
    trap 'rm -rf "${WORK}"' EXIT

    local name repo ref commit date target
    local old_commit new_commit new_date updated=0

    while IFS=$'\t' read -r name repo ref commit date target; do
        case "${name}" in
            ''|\#*) continue ;;
        esac
        [ -n "${target}" ] || { warning "skip ${name}: target column is empty"; continue; }

        step "checking ${name} (${repo}#${ref})"
        if ! git clone --quiet --depth 1 --branch "${ref}" "${repo}" "${WORK}/${name}"; then
            error "clone failed: ${repo}"
            return 1
        fi

        old_commit="${commit}"
        new_commit=$(git -C "${WORK}/${name}" rev-parse HEAD)
        new_date=$(git -C "${WORK}/${name}" log -1 --format='%cd' --date=short)

        if [ "${old_commit}" = "${new_commit}" ] && ! content_differs "${WORK}/${name}" "${REPO_ROOT}/${target}"; then
            info "${name}: already up to date (${new_commit:0:7})"
            continue
        fi

        if [ "${old_commit}" != "${new_commit}" ]; then
            step "${name}: ${old_commit:0:7} -> ${new_commit:0:7} (${new_date})"
        else
            warning "${name}: commit unchanged but local content differs, resyncing"
        fi

        if [ ${DRY_RUN} -eq 1 ]; then
            diff -rq --exclude=.git --exclude=tags "${REPO_ROOT}/${target}" "${WORK}/${name}" 2>/dev/null | head -20
            CHANGES+=("${name}: ${old_commit:0:7} -> ${new_commit:0:7} (dry-run)")
            updated=$((updated + 1))
            continue
        fi

        if [ -d "${REPO_ROOT}/${target}" ]; then
            sync_directory "${WORK}/${name}" "${REPO_ROOT}/${target}" || return 1
        else
            sync_file "${WORK}/${name}" "${REPO_ROOT}/${target}" || return 1
        fi

        update_manifest_row "${name}" "${new_commit}" "${new_date}" || return 1
        CHANGES+=("${name}: ${old_commit:0:7} -> ${new_commit:0:7} (${new_date})")
        updated=$((updated + 1))
    done < "${MANIFEST}"

    if [ ${DRY_RUN} -eq 1 ]; then
        if [ ${updated} -eq 0 ]; then
            success "all bundled components are up to date."
        else
            info "dry-run finished, ${updated} component(s) would be updated."
        fi
        return 0
    fi

    # 即便没有组件更新，也保证 README 与清单一致（清单可能被手工改过）
    step "refreshing README version table"
    "${REPO_ROOT}/scripts/update-readme.sh" || return 1

    if [ ${updated} -eq 0 ] && git diff --quiet -- pack vendor README.md; then
        success "all bundled components are up to date."
        return 0
    fi

    stage_and_commit || { info "working tree has no changes after sync."; return 0; }

    if [ ${PUSH} -eq 0 ]; then
        info "skip push (--no-push)."
        return 0
    fi
    push_changes || return 1
    return 0
}

main "$@"
