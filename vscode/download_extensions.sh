#!/usr/bin/env bash
# Подготовка входного файла:
#   Рядом с этим скриптом создайте файл vscode_extensions.txt в кодировке
#   UTF-8 без BOM. Каждое расширение указывайте на отдельной строке
#   в формате publisher.extension или publisher.extension@version.
#   Без @version скачивается последняя версия (latest).
#
#   Пример содержимого vscode_extensions.txt:
#     ms-python.python
#     charliermarsh.ruff
#     ms-python.python@2024.0.0
#
#   Используйте ID расширения, а не отображаемое имя или ссылку Marketplace.
#   В VS Code его можно получить через действие Copy Extension ID.
#   Для экспорта списка установленных расширений из Git Bash:
#     code --list-extensions > vscode_extensions.txt
#   Для списка с закреплёнными установленными версиями:
#     code --list-extensions --show-versions > vscode_extensions.txt
#   Эти команды требуют доступной в PATH команды code. Выполняйте их
#   из папки скрипта; перенаправление > заменяет существующий список.
#
#   Пустые строки и строки, начинающиеся с #, пропускаются.
#   Комментарии после ID в той же строке не поддерживаются.
#   Допустимы переводы строк Windows (CRLF) и Unix (LF).
#   Запуск: bash download_extensions.sh
#   Файлы VSIX сохраняются в соседнюю папку vscode_plugins;
#   расширения автоматически не устанавливаются.
#
# Файл: download_extensions.sh
# Windows 11 + Git Bash + Python
# Скачивает VS Code extensions в VSIX, не устанавливая их.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="$SCRIPT_DIR/vscode_extensions.txt"
OUTPUT_DIR="$SCRIPT_DIR/vscode_plugins"
FAILED_FILE="$SCRIPT_DIR/failed_downloads.txt"
LOG_FILE="$SCRIPT_DIR/download.log"

mkdir -p "$OUTPUT_DIR"
: > "$FAILED_FILE"
: > "$LOG_FILE"

log() {
    echo "$*" | tee -a "$LOG_FILE"
}

# Проверка зависимостей
for cmd in curl python; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Команда $cmd не найдена"
        exit 1
    fi
done

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "[ERROR] Не найден $INPUT_FILE"
    exit 1
fi

# Проверка ZIP и структуры VSIX
check_vsix() {
    python - "$1" <<'PY'
import sys
import zipfile

path = sys.argv[1]

try:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()

        if not any(
            name.lower().endswith("extension.vsixmanifest")
            for name in names
        ):
            sys.exit(1)

        if "extension/package.json" not in names:
            sys.exit(1)

        if archive.testzip() is not None:
            sys.exit(1)

except (OSError, zipfile.BadZipFile, RuntimeError):
    sys.exit(1)

sys.exit(0)
PY
}

download_extension() {
    local extension="$1"
    local name version publisher plugin
    local url filename destination tmp_file
    local http_code curl_status

    name="${extension%@*}"

    if [[ "$extension" == *"@"* ]]; then
        version="${extension##*@}"
    else
        version="latest"
    fi

    if [[ ! "$name" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ || ! "$version" =~ ^[A-Za-z0-9.+_-]+$ ]]; then
        log "[ERROR] Некорректный ID: $extension"
        return 1
    fi

    publisher="${name%%.*}"
    plugin="${name#*.}"

    url="https://marketplace.visualstudio.com/_apis/public/gallery/publishers/${publisher}/vsextensions/${plugin}/${version}/vspackage"

    filename="${name}-${version}.vsix"
    destination="$OUTPUT_DIR/$filename"
    tmp_file="${destination}.part"

    if [[ -f "$destination" ]]; then
        if check_vsix "$destination"; then
            log "[SKIP] $filename"
            return 2
        fi
        log "[WARN] Удаляю некорректный файл: $filename"
        rm -f "$destination"
    fi

    rm -f "$tmp_file"

    log "[DOWNLOAD] $extension"

    http_code=$(curl \
        --location \
        --compressed \
        --silent \
        --show-error \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 20 \
        --max-time 300 \
        --write-out "%{http_code}" \
        --output "$tmp_file" \
        "$url" 2>> "$LOG_FILE")

    curl_status=$?

    if [[ $curl_status -ne 0 || "$http_code" != "200" ]]; then
        log "[ERROR] HTTP $http_code, curl=$curl_status"
        rm -f "$tmp_file"
        return 1
    fi

    if ! check_vsix "$tmp_file"; then
        log "[ERROR] Файл не прошёл проверку VSIX"
        log "         $extension"
        log "         Размер: $(wc -c < "$tmp_file") байт"

        # Сохраняем ответ для диагностики
        mv -f "$tmp_file" "${destination}.invalid"
        return 1
    fi

    if ! mv -f "$tmp_file" "$destination"; then
        log "[ERROR] Не удалось сохранить $filename"
        return 1
    fi

    log "[OK] $filename"
    return 0
}

success=0
failed=0
skipped=0
total=0

log "========================================"
log " VS Code Extension Downloader"
log "========================================"
log "Источник: $INPUT_FILE"
log "Каталог:  $OUTPUT_DIR"

while IFS= read -r extension || [[ -n "$extension" ]]; do
    extension="${extension%$'\r'}"
    extension="${extension//[[:space:]]/}"

    [[ -z "$extension" || "$extension" == \#* ]] && continue

    ((total+=1))
    log ""
    log "[$total] Обработка: $extension"

    download_extension "$extension"
    status=$?

    case "$status" in
        0) ((success+=1)) ;;
        2) ((skipped+=1)) ;;
        *)
            ((failed+=1))
            echo "$extension" >> "$FAILED_FILE"
            ;;
    esac

done < "$INPUT_FILE"

log ""
log "========================================"
log " ИТОГИ"
log "========================================"
log "Всего:      $total"
log "Скачано:    $success"
log "Пропущено:  $skipped"
log "Ошибок:     $failed"
log "========================================"
log "VSIX:       $OUTPUT_DIR"
log "Лог:        $LOG_FILE"
log "Ошибки:     $FAILED_FILE"

# Ненулевой код позволяет обнаружить неполную загрузку.
(( failed == 0 ))
