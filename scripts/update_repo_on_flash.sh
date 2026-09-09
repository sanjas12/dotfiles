#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
ROOT_DIR="${1:-$SCRIPT_DIR}"
SPECIAL_FOLDERS=("Python" "Obsidian")
LOG_FILE="$SCRIPT_DIR/update_repo_on_flash.log"
# The foreground pipeline at the end waits until tee has written all output.
# Append so a later failed run does not erase earlier diagnostics.
if ! command -v tee >/dev/null 2>&1; then
    printf '[ERR] tee not found. Run this script using Git Bash or Bash.\n' >&2
    exit 1
fi
if ! : >> "$LOG_FILE"; then
    printf '[ERR] Cannot write log: %s\n' "$LOG_FILE" >&2
    exit 1
fi

total_ok=0 total_err=0 total_locks=0 total_dirty=0 total_skip=0

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

update_repo() {
    local repo name status output attempt pull_log branch setting value config_rc
    local upstream_missing=0
    local pull_codes=()
    repo=$(cd "$1" && pwd -P) || {
        printf '[ERR] Cannot access repository: %s\n' "$1"
        total_err=$((total_err + 1))
        return
    }
    name=$(basename "$repo")
    if status=$(cd "$repo" && GIT_OPTIONAL_LOCKS=0 git status --porcelain --untracked-files=normal 2>&1); then
        if [[ -n "$status" ]]; then
            total_dirty=$((total_dirty + 1))
            printf '[DIRTY] %s: local changes/untracked files detected\n' "$name"
            printf '%s\n' "$status"
        fi
    else
        printf '[WARN] %s: cannot check working tree: %s\n' "$name" "$status"
    fi
    # Check configuration, not whether the remote-tracking ref exists locally.
    # A configured but deleted/unfetched upstream must still go through pull.
    if branch=$(cd "$repo" && git symbolic-ref --quiet --short HEAD 2>/dev/null); then
        for setting in remote merge; do
            if value=$(cd "$repo" && git config --get "branch.$branch.$setting" 2>&1); then
                [[ -n "$value" ]] || upstream_missing=1
            else
                config_rc=$?
                if (( config_rc == 1 )); then
                    upstream_missing=1
                else
                    printf '[ERR] %s: cannot read upstream configuration: %s\n' "$name" "$value"
                    total_err=$((total_err + 1))
                    return
                fi
            fi
        done
        if (( upstream_missing == 1 )); then
            total_skip=$((total_skip + 1))
            printf '[SKIP] %s: branch %s has no configured upstream; pull skipped\n' "$name" "$branch"
            return
        fi
    fi
    for attempt in 1 2; do
        printf '[PULL] %s: attempt %s\n' "$name" "$attempt"
        pull_log=$(mktemp) || {
            printf '[ERR] %s: cannot create temporary diagnostics file\n' "$name"
            total_err=$((total_err + 1))
            return
        }
        (cd "$repo" && LC_ALL=C git pull) 2>&1 | tee "$pull_log"
        pull_codes=("${PIPESTATUS[@]}")
        output=$(cat "$pull_log")
        rm -- "$pull_log"
        if (( pull_codes[1] != 0 )); then
            printf '[ERR] %s: could not capture pull diagnostics\n' "$name"
            total_err=$((total_err + 1))
            return
        fi
        if (( pull_codes[0] == 0 )); then
            total_ok=$((total_ok + 1))
            printf '[OK] %s: pull completed\n' "$name"
            return
        fi
        if (( attempt == 1 )) && clear_stale_lock "$repo" "$output" "$name"; then
            continue
        fi
        total_err=$((total_err + 1))
        printf '[ERR] %s: pull failed (attempt %s); diagnostics above\n' "$name" "$attempt"
        return
    done
}

print_stats() {
    printf '[STAT] %s: successful=%s errors=%s locks_cleared=%s dirty=%s skipped=%s\n' "$@"
}

process_folder() {
    local folder_path="$1" prefixes="${2:-}"
    local before_ok=$total_ok before_err=$total_err before_locks=$total_locks before_dirty=$total_dirty
    local before_skip=$total_skip
    local item subitem name match p repo
    local repos=()
    if [[ ! -d "$folder_path" ]]; then
        printf '[ERR] Folder not found: %s\n' "$folder_path"
        print_stats "$(basename "$folder_path") (missing folder)" 0 0 0 0 0
        return
    fi
    # Preserve the original self / child / grandchild traversal and prefixes.
    if [[ -d "$folder_path/.git" ]]; then
        repos+=("$folder_path")
    else
        for item in "$folder_path"/*/; do
            [[ -d "$item" ]] || continue
            if [[ -n "$prefixes" ]]; then
                name=$(basename "$item")
                match=0
                for p in $prefixes; do
                    if [[ "$name" == "$p"* ]]; then match=1; break; fi
                done
                (( match == 1 )) || continue
            fi
            if [[ -d "$item/.git" ]]; then
                repos+=("$item")
            else
                for subitem in "$item"/*/; do
                    [[ -d "$subitem/.git" ]] || continue
                    repos+=("$subitem")
                done
            fi
        done
    fi
    printf '\n[DIR] Processing %s (%s repos)\n' "$(basename "$folder_path")" "${#repos[@]}"
    if (( ${#repos[@]} == 0 )); then
        printf '[WARN] No Git repositories found in %s\n' "$folder_path"
    fi
    for repo in "${repos[@]}"; do update_repo "$repo"; done
    print_stats "$(basename "$folder_path")" "$((total_ok-before_ok))" "$((total_err-before_err))" \
        "$((total_locks-before_locks))" "$((total_dirty-before_dirty))" "$((total_skip-before_skip))"
}

main() {
printf '\n==================================================\n[START] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf '[INFO] Script: %s\n[INFO] Root: %s\n[INFO] Log: %s\n' "${BASH_SOURCE[0]}" "$ROOT_DIR" "$LOG_FILE"
local dependency
for dependency in git mktemp cat rm stat ps uname date; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf '[ERR] Required command not found: %s\n' "$dependency"
        return 1
    fi
done
if [[ ! -d "$ROOT_DIR" ]]; then
    printf '[ERR] Root folder not found: %s\n' "$ROOT_DIR"
    return 1
fi
process_folder "$ROOT_DIR/Python"
process_folder "$ROOT_DIR/Obsidian"
for folder in "$ROOT_DIR"/*/; do
    [[ -d "$folder" ]] || continue
    name=$(basename "$folder")
    skip=0
    for special in "${SPECIAL_FOLDERS[@]}"; do
        if [[ "$name" == "$special" ]]; then skip=1; break; fi
    done
    (( skip == 1 )) && continue
    process_folder "$folder"
done
print_stats 'TOTAL' "$total_ok" "$total_err" "$total_locks" "$total_dirty" "$total_skip"
printf '[END] %s\n==================================================\n' "$(date '+%Y-%m-%d %H:%M:%S')"
(( total_err == 0 ))
}

main 2>&1 | tee -a "$LOG_FILE"
run_codes=("${PIPESTATUS[@]}")
if (( run_codes[1] != 0 )); then
    printf '[ERR] Writing log failed: %s\n' "$LOG_FILE" >&2
    exit 1
fi
exit "${run_codes[0]}"
