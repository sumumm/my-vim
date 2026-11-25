#!/usr/bin/env bash
# 用于验证 Vim 语法折叠：function、if、for、while、case

set -euo pipefail

MAX_ITEMS=8

label() {
    local id="$1"
    local name="$2"

    case $((id % 3)) in
        0) printf '%s: %%3 == 0\n' "$name" ;;
        1) printf '%s: %%3 == 1\n' "$name" ;;
        *) printf '%s: %%3 == 2\n' "$name" ;;
    esac
}

sum_even() {
    local total=0
    local value

    for value in "$@"; do
        if (( value % 2 != 0 )); then
            continue
        fi

        total=$(( total + value ))
    done

    printf '%s\n' "$total"
}

print_items() {
    local index=0

    while (( index < MAX_ITEMS )); do
        if (( index % 2 == 0 )); then
            label "$index" "item-$index"
        fi

        index=$(( index + 1 ))
    done
}

main() {
    local values=(1 2 3 4 5 6 7 8)

    printf 'sum of even values: %s\n' "$(sum_even "${values[@]}")"
    print_items
}

main "$@"
