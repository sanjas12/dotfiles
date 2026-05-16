import sys
import time
from pathlib import Path
from typing import Dict, Optional, Callable, Union

from PyQt5.QtCore import Qt, QThread, pyqtSignal
from PyQt5.QtWidgets import (
    QApplication,
    QComboBox,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QProgressDialog,
    QTableWidget,
    QVBoxLayout,
    QWidget,
    QAbstractItemView,
)

PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))


class MainWindowUI(QMainWindow):
    def __init__(self, version: str):
        super().__init__()

    def setup_ui(self, version: str) -> None:
        self.setWindowTitle(version)

        # Главный слой
        main_layout = QVBoxLayout()
        wid = QWidget(self)
        wid.setLayout(main_layout)
        self.setCentralWidget(wid)

    def show_error(self, message: str) -> None:
        """Показывает сообщение об ошибке"""
        QMessageBox.critical(self, "Ошибка", message)

if __name__ == "__main__":
    app = QApplication(sys.argv)

    main_window = MainWindowUI("Test")
    
    main_window.show()
    app.exec()
