import sys
import os

APP_DIR_NAME = "sakura-launcher-gui"
CONFIG_FILE = "sakura-launcher_config.json"
LOG_FILE_NAME = "sakura-launcher.log"


def get_resource_path(relative_path):
    if hasattr(sys, "_MEIPASS"):
        return os.path.join(sys._MEIPASS, relative_path)
    else:
        return os.path.join(os.path.abspath("."), relative_path)


def get_self_path():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    else:
        # 当前文件的绝对路径的上一级目录
        return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def is_packaged_linux():
    return sys.platform.startswith("linux") and getattr(sys, "frozen", False)


def get_xdg_dir(env_name, fallback):
    base_dir = os.environ.get(env_name)
    if not base_dir:
        base_dir = os.path.expanduser(fallback)
    path = os.path.join(base_dir, APP_DIR_NAME)
    os.makedirs(path, exist_ok=True)
    return path


def get_data_dir():
    if is_packaged_linux():
        return get_xdg_dir("XDG_DATA_HOME", "~/.local/share")
    return get_self_path()


def get_config_file_path():
    if is_packaged_linux():
        return os.path.join(
            get_xdg_dir("XDG_CONFIG_HOME", "~/.config"),
            CONFIG_FILE,
        )
    return os.path.abspath(CONFIG_FILE)


def get_log_file_path():
    if is_packaged_linux():
        return os.path.join(
            get_xdg_dir("XDG_STATE_HOME", "~/.local/state"),
            LOG_FILE_NAME,
        )
    return os.path.join(get_self_path(), LOG_FILE_NAME)


CURRENT_DIR = get_data_dir()
LOG_FILE = get_log_file_path()
ICON_FILE = "icon.ico"
GHPROXY_URL = "ghfast.top"
SAKURA_LAUNCHER_GUI_VERSION = "v1.2.0-beta"
DEBUG_BUILD = False

processes = []
