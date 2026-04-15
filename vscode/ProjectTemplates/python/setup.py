import os
import platform
import shutil
import sys
from typing import List, Tuple

from cx_Freeze import Executable, setup  # type: ignore

from src.version import __app_name__, __revision__, __version__

_sys = platform.system().lower()
if _sys == "darwin":
    _sys = "macos"
elif _sys == "windows":
    _sys = "win"
_arch = platform.machine().lower()

_py = f"{sys.version_info.major}.{sys.version_info.minor}"

# TG-Naladka.win-amd64-3.11-0.3.1r42
output_name = f"{__app_name__}.{_sys}-{_arch}-{_py}-{__version__}{__revision__}"

project_root = os.path.dirname(os.path.abspath(__file__))
src_root = os.path.join(project_root, "src")
build_dir = os.path.join("build", output_name)          # ← единый источник пути сборки

# ---------------------------------------------------------------------------
# Файлы для включения
# ---------------------------------------------------------------------------
def get_include_files() -> List[Tuple[str, str]]:
    files: List[Tuple[str, str]] = []

    config_path = os.path.join(src_root, "config", "config.py")
    if os.path.exists(config_path):
        files.append((config_path, "config/config.py"))

    relnote_dir = os.path.join(project_root, "Documentation", "RelNote")
    if os.path.isdir(relnote_dir):
        files.append((relnote_dir, "Documentation/RelNote"))

    return files

# Имя исполняемого файла: с .exe на Windows, без — на остальных
exe_name = __app_name__ + (".exe" if sys.platform == "win32" else "")

# Сборка
build_options = { # type: ignore
    "path": sys.path + [src_root],
    "excludes": [
        "matplotlib.tests",
        "matplotlib.testing",
        "pandas.tests",
        "scipy",
        "PyQt5.QtWebEngine",
        "PyQt5.QtNetwork",
        "PyQt5.QtSql",
        "PyQt5.QtScript",
        "PyQt5.QtSvg",
        "PyQt5.QtTest",
        "PyQt5.QtXml",
        "PyQt5.QtDesigner",
        "PyQt5.QtMultimedia",
        "PyQt5.QtMultimediaWidgets",
        "PyQt5.QtOpenGL",
        "PyQt5.QtPrintSupport",
        "PyQt5.QtQml",
        "debugpy",
        "distutils",
    ],
    "optimize": 2,
    "include_files": get_include_files(),
    "build_exe": build_dir,           # ← используем переменную
}

setup(
    name=__app_name__,
    version=__version__,
    description="TG Analysis Tool",
    options={"build_exe": build_options},
    executables=[
        Executable(
            os.path.join(src_root, "main.py"),
            target_name=exe_name,    # ← без жёсткого .exe
            # base="Win32GUI",       # раскомментировать чтобы скрыть консоль на Windows
        )
    ],
)

# ---------------------------------------------------------------------------
# Пост-обработка: удаляем мусор после сборки
# ---------------------------------------------------------------------------
REMOVE_DIRS = [
    "PyQt5/Qt5/translations",
    # "matplotlib/mpl-data/sample_data",
    # "matplotlib/mpl-data/stylelib",
]

lib_path = os.path.join(build_dir, "lib")   # ← теперь совпадает с реальным путём

for rel in REMOVE_DIRS:
    path = os.path.join(lib_path, rel)
    if os.path.isdir(path):
        shutil.rmtree(path)
        print(f"[CLEAN] Удалено: {path}")
    else:
        print(f"[SKIP]  Не найдено: {path}")