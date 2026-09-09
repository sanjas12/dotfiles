#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
SPECIAL_FOLDERS=("Python" "Obsidian")
LOG_FILE="$SCRIPT_DIR/update_repo_on_flash.log"
exec > >(tee "$LOG_FILE") 2>&1

total_ok=0 total_err=0 total_locks=0 total_dirty=0

# Return 0 only if a complete process snapshot contains no Git processes.
# Conservative across repositories: cwd alone cannot identify git -C, --git-dir,
# worktrees or inherited GIT_DIR. An unrelated Git process also prevents cleanup.
# Windows ps does not reliably include native processes; query Windows instead.
git_is_idle() {
    local processes process
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            command -v powershell.exe >/dev/null 2>&1 || return 1
            processes=$(powershell.exe -NoProfile -NonInteractive -Command \
                '$ErrorActionPreference = "Stop"; try { Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match "^(git($|[-.])|scalar($|[.]))" } | ForEach-Object { $_.Id } } catch { exit 1 }' 2>/dev/null) || return 1
            processes=${processes//$'\r'/}
            [[ -z "$processes" ]]
            ;;
        Linux*)
            processes=$(ps -e -o comm= 2>/dev/null) || return 1
            [[ -n "$processes" ]] || return 1
            while IFS= read -r process; do
                case "$process" in
                    git|git-*|git.exe|scalar|scalar.exe) return 1 ;;
                esac
            done <<< "$processes"
            return 0
            ;;
        *) return 1 ;;
    esac
}

# Clear only a known lock explicitly named in the failed pull's diagnostics.
# Never glob-delete locks. Young/changing locks and symlinks are left untouched.
# A process snapshot cannot prevent another program starting just afterwards:
# do not run concurrent Git/IDE updates while this script is repairing locks.
clear_stale_lock() {
    local repo="$1" output="$2" name="$3"
    local key lock signature current mtime now
    [[ "$output" == *'File exists'* ]] || return 1
    for key in ORIG_HEAD index packed-refs shallow; do
        lock=$(cd "$repo" && git rev-parse --git-path "$key.lock") || continue
        case "$lock" in
            /*|[A-Za-z]:/*) ;;
            *) lock="$repo/$lock" ;;
        esac
        # Compare the diagnostic's quoted path, with Windows/relative variants.
        local relative native
        relative=$(cd "$repo" && git rev-parse --git-path "$key.lock") || continue
        native="$lock"
        if command -v cygpath >/dev/null 2>&1; then
            native=$(cygpath -am "$lock") || continue
        fi
        if [[ "$output" != *"'$lock'"* && "$output" != *"'$relative'"* && "$output" != *"'$native'"* ]]; then
            continue
        fi
        printf '[LOCK] %s: detected %s\n' "$name" "$lock"
        if [[ ! -f "$lock" || -L "$lock" ]]; then
            printf '[WARN] %s: lock disappeared or is not a regular file; kept\n' "$name"
            return 1
        fi
        signature=$(stat -c '%d:%i:%s:%Y:%Z:%y:%z' -- "$lock" 2>/dev/null) || return 1
        mtime=$(stat -c '%Y' -- "$lock" 2>/dev/null) || return 1
        now=$(date +%s) || return 1
        if [[ ! "$mtime" =~ ^[0-9]+$ ]] || (( now - mtime < 60 )); then
            printf '[WARN] %s: lock is younger than 60 seconds or has a future timestamp; kept\n' "$name"
            return 1
        fi
        if ! git_is_idle; then
            printf '[WARN] %s: Git process active or process check unavailable; lock kept\n' "$name"
            return 1
        fi
        current=$(stat -c '%d:%i:%s:%Y:%Z:%y:%z' -- "$lock" 2>/dev/null) || return 1
        if [[ "$signature" != "$current" || -L "$lock" ]]; then
            printf '[WARN] %s: lock changed during inspection; kept\n' "$name"
            return 1
        fi
        if rm -- "$lock"; then
            total_locks=$((total_locks + 1))
            printf '[LOCK] %s: stale lock cleared; retrying pull once\n' "$name"
            return 0
        fi
        printf '[WARN] %s: could not remove lock\n' "$name"
        return 1
    done
    if [[ "$output" == *'.lock'* ]]; then
        printf '[LOCK] %s: unrecognised lock; automatic removal skipped\n' "$name"
    fi
    return 1
}
