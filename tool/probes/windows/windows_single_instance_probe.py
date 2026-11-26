import argparse
import ctypes
import os
import shutil
import subprocess
import tempfile
import time
import uuid
from ctypes import wintypes
from pathlib import Path


def win_function(name, result, *arguments):
    function = getattr(ctypes.windll.user32, name)
    function.restype = result
    function.argtypes = arguments
    return function


window_callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
enum_windows = win_function("EnumWindows", wintypes.BOOL, window_callback, wintypes.LPARAM)
foreground_window = win_function("GetForegroundWindow", wintypes.HWND)
window_pid = win_function(
    "GetWindowThreadProcessId",
    wintypes.DWORD,
    wintypes.HWND,
    ctypes.POINTER(wintypes.DWORD),
)
window_title = win_function(
    "GetWindowTextW", ctypes.c_int, wintypes.HWND, wintypes.LPWSTR, ctypes.c_int
)
is_visible = win_function("IsWindowVisible", wintypes.BOOL, wintypes.HWND)
is_iconic = win_function("IsIconic", wintypes.BOOL, wintypes.HWND)
is_zoomed = win_function("IsZoomed", wintypes.BOOL, wintypes.HWND)
show_window = win_function("ShowWindowAsync", wintypes.BOOL, wintypes.HWND, ctypes.c_int)
post_message = win_function(
    "PostMessageW",
    wintypes.BOOL,
    wintypes.HWND,
    wintypes.UINT,
    wintypes.WPARAM,
    wintypes.LPARAM,
)
get_layered_attributes = win_function(
    "GetLayeredWindowAttributes",
    wintypes.BOOL,
    wintypes.HWND,
    ctypes.POINTER(wintypes.DWORD),
    ctypes.POINTER(wintypes.BYTE),
    ctypes.POINTER(wintypes.DWORD),
)


def main_window(process=None):
    matches = []

    @window_callback
    def find(window, _):
        owner = wintypes.DWORD()
        window_pid(window, ctypes.byref(owner))
        if process is None or owner.value == process.pid:
            title = ctypes.create_unicode_buffer(64)
            window_title(window, title, len(title))
            if title.value == "PiliAuroraNext":
                matches.append(window)
        return True

    enum_windows(find, 0)
    return next(iter(matches), None)


def displayed(window):
    alpha = wintypes.BYTE()
    return is_visible(window) and not is_iconic(window) and (
        not get_layered_attributes(window, None, ctypes.byref(alpha), None)
        or alpha.value == 255
    )


def wait_for(condition, failure, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if result := condition():
            return result
        time.sleep(0.05)
    raise AssertionError(failure)


def assert_relaunch_exits(process):
    def finished():
        if process.poll() is not None:
            return (process.returncode,)
        window = main_window(process)
        assert not window or not displayed(window), "重复启动显示了第二个主窗口"
        return None

    (exit_code,) = wait_for(finished, "重复启动没有退出")
    assert exit_code == 0, f"重复启动以错误码 {exit_code} 退出"


def stage_runner(source, target, product_name):
    shutil.copytree(source.parent, target, copy_function=os.link)
    executable = target / source.name
    executable.unlink()
    binary = source.read_bytes()
    key = "ProductName\0".encode("utf-16-le")
    value = "PiliAuroraNext\0".encode("utf-16-le")
    value_offset = binary.index(key) + len(key)
    value_offset = (value_offset + 3) & ~3
    assert binary[value_offset : value_offset + len(value)] == value
    new_value = f"{product_name}\0".encode("utf-16-le")
    assert len(new_value) == len(value)
    executable.write_bytes(
        binary[:value_offset] + new_value + binary[value_offset + len(value) :]
    )
    return executable


def run(source, require_foreground):
    assert not main_window(), "请先退出正在运行的 PiliAuroraNext（包括托盘驻留）"
    processes = []
    product_name = f"PAN{uuid.uuid4().hex[:11]}"
    roaming = Path(os.environ["APPDATA"]).resolve(strict=True)
    support_path = roaming / "wallpap" / product_name
    assert not support_path.exists()
    with tempfile.TemporaryDirectory(dir=source.parent.parent) as directory:
        staging = Path(directory)
        primary = stage_runner(source, staging / "primary", product_name)
        alternate = stage_runner(source, staging / "alternate", product_name)

        def start(executable, *arguments):
            process = subprocess.Popen([executable, *arguments], cwd=executable.parent)
            processes.append(process)
            return process

        try:
            cold_starts = [start(primary), start(primary), start(alternate)]

            def find_host():
                for process in cold_starts:
                    window = main_window(process)
                    if window and displayed(window):
                        return process, window
                return None

            host, window = wait_for(find_host, "冷启动主窗口没有显示")
            assert (support_path / "hive").is_dir(), "未使用隔离的应用数据目录"
            for duplicate in cold_starts:
                if duplicate is not host:
                    assert_relaunch_exits(duplicate)
            assert_relaunch_exits(start(alternate))
            print("并发冷启动和跨目录重复启动只保留一个主窗口", flush=True)

            show_window(window, 3)
            wait_for(lambda: is_zoomed(window), "主窗口未最大化")
            show_window(window, 6)
            wait_for(lambda: is_iconic(window), "主窗口未最小化")
            assert_relaunch_exits(start(primary))
            wait_for(lambda: displayed(window) and is_zoomed(window), "未恢复最大化窗口")
            print("重复启动恢复最小化前的最大化状态", flush=True)

            assert post_message(window, 0x0010, 0, 0)
            wait_for(
                lambda: not is_visible(window) and host.poll() is None,
                "关闭没有将主窗口隐藏到托盘",
            )
            assert_relaunch_exits(start(primary))
            wait_for(lambda: displayed(window), "托盘窗口未恢复显示或仍然透明")
            print("重复启动恢复托盘窗口并解除透明状态", flush=True)
            if require_foreground:
                wait_for(lambda: foreground_window() == window, "恢复后主窗口未获得前台焦点")
                print("主窗口获得前台焦点", flush=True)
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=10)
            if support_path.exists():
                assert support_path.resolve(strict=True) == support_path
                shutil.rmtree(support_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="验证 Windows 主窗口的单实例与重复启动行为")
    parser.add_argument("executable", type=Path)
    parser.add_argument("--require-foreground", action="store_true")
    options = parser.parse_args()
    run(options.executable.resolve(strict=True), options.require_foreground)
