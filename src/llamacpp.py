import logging
import os
import re
import shutil
import subprocess
import sys
import tarfile
from typing import Dict, List
import zipfile

from PySide6.QtCore import QObject, Signal

from .common import GHPROXY_URL


class Llamacpp:
    repo: str
    filename: str
    version: str
    gpu: str
    require_cuda: bool
    platforms: List[str]
    download_links: Dict[str, str]

    def __init__(
        self,
        repo: str,
        filename: str,
        version: str,
        gpu: str,
        require_cuda: bool,
        platforms: List[str] | None = None,
    ):
        self.repo = repo
        self.version = version
        self.gpu = gpu
        self.filename = filename
        self.require_cuda = require_cuda
        self.platforms = platforms or []
        github_repo = f"https://github.com/{repo}/{filename}"
        self.download_links = {
            "GHProxy": f"https://{GHPROXY_URL}/" + github_repo,
            "GitHub": github_repo,
        }


class LlamacppList(QObject):
    DOWNLOAD_SRC = [
        "GHProxy",
        "GitHub",
    ]
    CUDART = {
        "filename": "cudart-llama-bin-win-cuda-12.4-x64.zip",
        "download_links": {
            "GitHub": "https://github.com/ggml-org/llama.cpp/releases/download/b6178/cudart-llama-bin-win-cuda-12.4-x64.zip",
            "GHProxy": f"https://{GHPROXY_URL}/https://github.com/ggml-org/llama.cpp/releases/download/b6178/cudart-llama-bin-win-cuda-12.4-x64.zip",
        },
    }
    _list: List[Llamacpp] = []
    changed = Signal(list)

    def __init__(self, parent=None):
        super().__init__(parent)

    @staticmethod
    def _current_platform():
        if sys.platform == "win32":
            return "windows"
        if sys.platform == "darwin":
            return "macos"
        if sys.platform.startswith("linux"):
            return "linux"
        return sys.platform

    def _supports_current_platform(self, obj):
        platform_key = self._current_platform()
        platforms = obj.get("platforms")
        if platforms:
            return platform_key in platforms

        filename = obj.get("filename", "").lower()
        if platform_key == "windows":
            return "win-" in filename or "-win" in filename
        if platform_key == "macos":
            return "macos" in filename
        if platform_key == "linux":
            return "ubuntu" in filename or "linux" in filename
        return True

    def update_llamacpp_list(self, data_json):
        llamacpp_list = []
        for obj in data_json["llamacpp"]:
            if not self._supports_current_platform(obj):
                continue
            llamacpp = Llamacpp(
                repo=obj["repo"],
                filename=obj["filename"],
                version=obj["version"],
                gpu=obj["gpu"],
                require_cuda=obj["require_cuda"],
                platforms=obj.get("platforms"),
            )
            llamacpp_list.append(llamacpp)
        if not llamacpp_list and self._list:
            logging.warning("远程 llama.cpp 列表没有当前平台可用项，保留本地列表")
            return
        self._list = llamacpp_list
        self.changed.emit(llamacpp_list)

    def __iter__(self):
        for item in self._list:
            yield item


LLAMACPP_LIST = LlamacppList()


def _replace_path(src_path: str, dst_path: str):
    if os.path.exists(dst_path):
        if os.path.isdir(dst_path) and not os.path.islink(dst_path):
            shutil.rmtree(dst_path)
        else:
            os.remove(dst_path)
    shutil.move(src_path, dst_path)


def _flatten_llamacpp_bin_folder(llama_folder: str):
    bin_folder = os.path.join(llama_folder, "build", "bin")
    if os.path.isdir(bin_folder):
        for item in os.listdir(bin_folder):
            _replace_path(
                os.path.join(bin_folder, item),
                os.path.join(llama_folder, item),
            )
        shutil.rmtree(os.path.join(llama_folder, "build"))


def _make_linux_binaries_executable(llama_folder: str):
    if sys.platform == "win32":
        return
    for filename in ("llama-server", "llama-batched-bench"):
        path = os.path.join(llama_folder, filename)
        if os.path.isfile(path):
            os.chmod(path, 0o755)


def unzip_llamacpp(folder: str, filename: str):
    llama_folder = os.path.join(folder, "llama")
    file_path = os.path.join(folder, filename)
    print(f"将解压 {filename} 到 {llama_folder}")

    os.makedirs(llama_folder, exist_ok=True)

    # 解压，如果文件已存在则覆盖
    if filename.endswith(".zip"):
        with zipfile.ZipFile(file_path, "r") as zip_ref:
            zip_ref.extractall(llama_folder)
    elif filename.endswith(".tar.gz") or filename.endswith(".tgz"):
        with tarfile.open(file_path, "r:gz") as tar_ref:
            tar_ref.extractall(llama_folder)
    else:
        print(f"不支持的文件格式: {filename}")
        return

    _flatten_llamacpp_bin_folder(llama_folder)
    _make_linux_binaries_executable(llama_folder)
    print(f"{filename} 已成功解压到 {llama_folder}")


def is_cudart_exist(folder: str):
    llama_folder = os.path.join(folder, "llama")
    for filename in [
        "cublas64_12.dll",
        "cublasLt64_12.dll",
        "cudart64_12.dll",
    ]:
        if not os.path.exists(os.path.join(llama_folder, filename)):
            return False
    return True


def get_llamacpp_version(llamacpp_path: str):
    exe_extension = ".exe" if sys.platform == "win32" else ""
    executable_path = os.path.join(llamacpp_path, f"llama-server{exe_extension}")
    try:
        logging.info(f"尝试执行命令: {executable_path} --version")
        result = subprocess.run(
            [executable_path, "--version"],
            capture_output=True,
            text=True,
            timeout=2,
            shell=os.name == "nt",
        )
        version_output = result.stderr.strip()  # 使用 stderr 而不是 stdout
        logging.info(f"版本输出: {version_output}")
        version_match = re.search(r"version: (\d+)", version_output)
        if version_match:
            return int(version_match.group(1))
        else:
            logging.info("无法匹配版本号")
    except subprocess.TimeoutExpired as e:
        logging.info(f"获取llama.cpp版本超时: {e.stdout}, {e.stderr}")
    except Exception as e:
        logging.info(f"获取llama.cpp版本时出错: {str(e)}")
    return None
