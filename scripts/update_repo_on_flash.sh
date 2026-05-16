#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECIAL_FOLDERS=("Python" "Obsidian")

process_folder() {
    local folder_path="$1"
    local prefixes="$2"  # необязательный, например "0 1 2 3"

    if [ ! -d "$folder_path" ]; then
        echo "[ERR] Folder not found: $folder_path"
        return
    fi

    # Если сама папка является Git-репозиторием — обновляем её напрямую
    if [ -d "$folder_path/.git" ]; then
        echo ""
        echo "[DIR] Processing $(basename "$folder_path") (self repo)"
        echo "--------------------------------------------------"
        if (cd "$folder_path" && git pull); then
            echo "[STAT] $(basename "$folder_path"): 1/1 successful"
        else
            echo "[STAT] $(basename "$folder_path"): 0/1 successful"
        fi
        return
    fi

    # Собираем список репозиториев внутри папки
    local repos=()
    for item in "$folder_path"/*/; do
        [ -d "$item/.git" ] || continue

        # Применяем префиксы если заданы
        if [ -n "$prefixes" ]; then
            local name
            name="$(basename "$item")"
            local match=0
            for p in $prefixes; do
                if [[ "$name" == "$p"* ]]; then
                    match=1
                    break
                fi
            done
            [ $match -eq 1 ] || continue
        fi

        repos+=("$item")
    done

    if [ ${#repos[@]} -eq 0 ]; then
        echo "[WARN] No Git repositories found in $folder_path"
        return
    fi

    echo ""
    echo "[DIR] Processing $(basename "$folder_path") (${#repos[@]} repos)"
    echo "--------------------------------------------------"

    local success_count=0
    for repo in "${repos[@]}"; do
        local name
        name="$(basename "$repo")"
        if output=$(cd "$repo" && git pull 2>&1); then
            echo "[OK]  $name: $output"
            ((success_count++))
        else
            echo "[ERR] $name: $output"
        fi
    done

    echo ""
    echo "[STAT] $(basename "$folder_path"): $success_count/${#repos[@]} successful"
}

# Обрабатываем Python (папки начинающиеся с 0, 1, 2, 3)
process_folder "$SCRIPT_DIR/Python" "0 1 2 3"

# Обрабатываем Obsidian (все папки)
process_folder "$SCRIPT_DIR/Obsidian"

# Обрабатываем все остальные папки рядом со скриптом
for folder in "$SCRIPT_DIR"/*/; do
    name="$(basename "$folder")"

    # Пропускаем специальные папки
    skip=0
    for special in "${SPECIAL_FOLDERS[@]}"; do
        if [ "$name" == "$special" ]; then
            skip=1
            break
        fi
    done
    [ $skip -eq 1 ] && continue

    process_folder "$folder"
done

echo ""
echo "All done!"
