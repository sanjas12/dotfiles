#0.0.1
import sys
import os
from cx_Freeze import setup, Executable

# Получаем текущую версию из первой строки файла
version = open(__file__, 'r', encoding='utf-8').readline().strip('#').strip()

# Определяем базовые пути
project_root = os.path.dirname(os.path.abspath(__file__))
src_root = os.path.join(project_root, 'tg-naladka', 'src')

# Функция для умного включения файлов
def get_smart_includes():
    include_files = []
    
    # Добавляем только необходимые конфигурационные файлы
    config_path = os.path.join(src_root, 'config', 'config.py')
    if os.path.exists(config_path):
        include_files.append((config_path, 'config/config.py'))
    
    # Добавляем каталог с релизными заметками, если он существует
    doc_dir = os.path.join(project_root, 'tg-naladka', 'Documentation')
    relnote_dir = os.path.join(doc_dir, 'RelNote')
    if os.path.isdir(relnote_dir):
        include_files.append((relnote_dir, 'Documentation/RelNote'))
    
    return include_files

# Собираем файлы для включения в сборку
include_files = get_smart_includes()

# Настройки сборки
build_exe_options = {
    "path": sys.path + [src_root],
    "excludes": [
        "matplotlib.tests", "matplotlib.testing", "pandas.tests", "scipy.tests",
        "PyQt5.QtWebEngine", "PyQt5.QtNetwork", "PyQt5.QtSql",
        "PyQt5.QtScript", "PyQt5.QtSvg", "PyQt5.QtTest",
        "PyQt5.QtXml", "PyQt5.QtDesigner", "PyQt5.QtMultimedia",
        "PyQt5.QtMultimediaWidgets", "PyQt5.QtOpenGL", "PyQt5.QtPrintSupport",
        "PyQt5.QtQml",
    ],
    "optimize": 0, # c 2 - 477 Mb (3.11), c 1 или 0 - 175 Mb (3.11) 
    "include_files": include_files,
}


setup(
    name="TG-Naladka",
    version=version,
    description="TG Analysis Tool",
    options={"build_exe": build_exe_options},
    executables=[
        Executable(
            os.path.join(src_root, "main.py"),
            target_name="TG-Naladka.exe",
            # base=None if sys.platform != "win32" else "Win32GUI",  # - командная строка если закоменчена то, она появляется
        )
    ],
)
