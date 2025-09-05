import logging
import sys
from pathlib import Path
from typing import Optional

from PyQt5.QtWidgets import QApplication

try:
    from win32api import GetFileVersionInfo, error as win32_error
    WIN32_AVAILABLE = True
except ImportError:
    WIN32_AVAILABLE = False
    win32_error = Exception

import config.config as cfg
from logic.logic import MainLogic
from ui.MainWindowUI import MainWindowUI


def _get_version_from_frozen_exe() -> Optional[str]:
    """
    Возвращает номер версии из исполняемого файла или setup.py.

    Returns:
        Optional[str]: Номер версии в формате '#X.Y.Z' или None при ошибке
    """
    try:
        version_info = GetFileVersionInfo(sys.argv[0], "\\")  # type: ignore
        version = (
            version_info["FileVersionMS"] // 65536,
            version_info["FileVersionMS"] % 65536,
            version_info["FileVersionLS"] // 65536,
        )
        return f"#{'.'.join(map(str, version))}"
    except (win32_error, KeyError, Exception):
        return None


def _get_version_from_setup() -> Optional[str]:
    """Получение версии из корневого `setup.py` (первая строка вида `#0.1.26`)."""
    try:
        # main.py находится в `tg-naladka/src/main.py`, поэтому корень репо — на два уровня выше
        setup_path = Path(__file__).resolve().parents[2] / "setup.py"
        if not setup_path.exists():
            return None
        first_line = setup_path.read_text(encoding="utf-8").splitlines()[0].strip()
        if first_line.startswith("#") and len(first_line) > 1:
            return f"#{first_line.lstrip('#').strip()}"
    except Exception:
        return None
    return None


def get_version() -> Optional[str]:
    """Возвращает версию приложения из exe, затем из setup.py"""
    if getattr(sys, "frozen", False):
        v = _get_version_from_frozen_exe()
        if v:
            return v
    return _get_version_from_setup() or None


def setup_logging() -> None:
    """Настраивает систему логирования."""
    logging.basicConfig(
        filename=cfg.LOG_FILE,
        level=cfg.LEVEL_LOG,
        format=cfg.FORMAT,
        filemode="a",
    )
    logging.info("Запуск приложения")


def main() -> None:
    """Точка входа в приложение."""
    setup_logging()

    try:
        app = QApplication(sys.argv)
        app.setStyleSheet(f"* {{ font-size: {cfg.FONT_SIZE}pt; font-family: Arial; }}")

        main_window = MainWindowUI(get_version() or "Неизвестно")
        MainLogic(main_window)  # Инъекция зависимости

        main_window.show()
        sys.exit(app.exec_())
    except Exception as e:
        logging.critical("Критическая ошибка", exc_info=True)
        raise
    finally:
        logging.info("Приложение завершено")


if __name__ == "__main__":
    main()
 