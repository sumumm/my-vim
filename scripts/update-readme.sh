#!/bin/bash
# =====================================================
# Copyright © hk. 2022-2026. All rights reserved.
# File name : update-readme.sh
# Author  : 苏木
# Date    : 2026-11-22
# Description: 依据 pack/plugins.tsv 重新生成 README.md 中的「内置组件版本」表格
# Usage   : scripts/update-readme.sh [--check]
#   --check  只检查 README 是否与清单一致，不写文件；不一致时返回 1
# =====================================================

SCRIPT_NAME=${0##*/}
REPO_ROOT=$(cd "$(dirname "${0}")/.." >/dev/null 2>&1 && pwd)
MANIFEST="${REPO_ROOT}/pack/plugins.tsv"
README="${REPO_ROOT}/README.md"

# 自动生成区块的标记，README 中必须存在
BEGIN_MARK="<!-- BEGIN AUTOGEN:components -->"
END_MARK="<!-- END AUTOGEN:components -->"

CHECK_ONLY=0
if [ "$1" = "--check" ]; then
    CHECK_ONLY=1
fi

# 颜色和日志标识
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

if [ ! -f "${MANIFEST}" ]; then
    error "manifest not found: ${MANIFEST}"
    exit 1
fi
if [ ! -f "${README}" ]; then
    error "readme not found: ${README}"
    exit 1
fi
if ! grep -qF "${BEGIN_MARK}" "${README}"; then
    error "marker missing in ${README}: ${BEGIN_MARK}"
    exit 1
fi

tmp_table=$(mktemp) || exit 1
tmp_readme=$(mktemp) || exit 1
trap 'rm -f "${tmp_table}" "${tmp_readme}"' EXIT

# 由 TSV 生成 markdown 表格
{
    printf '| 组件 | 上游仓库 | 跟踪 | 提交 | 日期 |\n'
    printf '|---|---|---|---|---|\n'
    awk -F'\t' '
        /^#/ { next }
        NF < 5 { next }
        {
            repo = $2
            n = split(repo, parts, "/")
            name = parts[n]
            sub(/\.git$/, "", name)
            printf "| %s | [%s](%s) | %s | [`%s`](%s/commit/%s) | %s |\n", \
                $1, name, repo, $3, substr($4, 1, 7), repo, $4, $5
        }
    ' "${MANIFEST}"
} > "${tmp_table}"

if [ ! -s "${tmp_table}" ]; then
    error "manifest has no valid rows: ${MANIFEST}"
    exit 1
fi

# 替换标记之间的内容，标记本身保留
awk -v b="${BEGIN_MARK}" -v e="${END_MARK}" -v t="${tmp_table}" '
    $0 == b {
        print
        while ((getline line < t) > 0) {
            print line
        }
        close(t)
        skip = 1
        next
    }
    skip && $0 == e {
        skip = 0
    }
    !skip { print }
' "${README}" > "${tmp_readme}" || exit 1

if cmp -s "${tmp_readme}" "${README}"; then
    info "README is already up to date."
    exit 0
fi

if [ ${CHECK_ONLY} -eq 1 ]; then
    error "README version table is out of date, run ${SCRIPT_NAME} to refresh."
    exit 1
fi

step "updating version table in ${README}"
cp -f "${tmp_readme}" "${README}" || exit 1
success "README version table updated."
