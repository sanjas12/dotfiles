#!/usr/bin/env python3
"""
Параллельное обновление Git-репозиториев
"""

import subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Tuple, List


def update_repo(repo_path: Path) -> Tuple[str, bool, str]:
    """Обновляет один репозиторий и возвращает результат"""
    try:
        result = subprocess.run(
            ["git", "pull"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=60,  # 60 секунд таймаут
        )

        if result.returncode == 0:
            output = result.stdout.strip() or "Already up to date"
            return (repo_path.name, True, output)
        else:
            error = result.stderr.strip()
            return (repo_path.name, False, error)
    except subprocess.TimeoutExpired:
        return (repo_path.name, False, "Timeout after 60 seconds")
    except Exception as e:
        return (repo_path.name, False, str(e))


def process_folder(folder_path: Path, prefixes: List[str] = None, max_workers: int = 4):
    """Обрабатывает все репозитории в папке параллельно"""

    if not folder_path.exists():
        print(f"[ERR] Folder not found: {folder_path}")
        return

    # Если сама папка является Git-репозиторием — обновляем её напрямую
    if (folder_path / ".git").is_dir():
        name, success, message = update_repo(folder_path)
        status = "[OK] " if success else "[ERR]"
        print(f"\n[DIR] Processing {folder_path.name} (self repo)")
        print("-" * 50)
        print(f"{status} {name}: {message}")
        print(f"\n[STAT] {folder_path.name}: {'1/1' if success else '0/1'} successful")
        return

    # Находим все Git-репозитории внутри папки
    repos = []
    for item in folder_path.iterdir():
        if item.is_dir() and (item / ".git").is_dir():
            # Применяем префиксы если заданы
            if prefixes and not any(item.name.startswith(p) for p in prefixes):
                continue
            repos.append(item)

    if not repos:
        print(f"[WARN] No Git repositories found in {folder_path}")
        return

    print(f"\n[DIR] Processing {folder_path.name} ({len(repos)} repos)")
    print("-" * 50)

    # Параллельное обновление
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(update_repo, repo): repo for repo in repos}

        success_count = 0
        for future in as_completed(futures):
            name, success, message = future.result()
            if success:
                print(f"[OK]  {name}: {message}")
                success_count += 1
            else:
                print(f"[ERR] {name}: {message}")

    print(f"\n[STAT] {folder_path.name}: {success_count}/{len(repos)} successful")


def main():
    script_dir = Path(__file__).parent

    # Папки с особой обработкой
    SPECIAL_FOLDERS = {"Python", "Obsidian"}

    # Обрабатываем Python (папки начинающиеся с 0, 1, 2, 3)
    process_folder(script_dir / "Python", prefixes=["0", "1", "2", "3"])

    # Обрабатываем Obsidian (все папки)
    process_folder(script_dir / "Obsidian")

    # Обрабатываем все остальные папки рядом со скриптом
    for folder in sorted(script_dir.iterdir()):
        if folder.is_dir() and folder.name not in SPECIAL_FOLDERS:
            process_folder(folder)

    print("\nAll done!")


if __name__ == "__main__":
    main()