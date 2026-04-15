import subprocess


def git_revision() -> str:
    try:
        count = subprocess.check_output(
            ["git", "rev-list", "--count", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL  # подавляем ошибки git в консоль
        ).strip()
        return f"r{count}"
    except Exception:
        return "r0"

__version__ = "0.3.1"
__revision__ = git_revision()
__app_name__ = "TG-Naladka"
__full_version__ = f"{__app_name__}-{__version__}{__revision__}"