"""The only owner of test-process creation, reaping and failure cleanup."""

from contextlib import contextmanager
import subprocess
import threading


@contextmanager
def owned_process(command, *, stdout, stderr):
    process = subprocess.Popen(command, stdout=stdout, stderr=stderr, text=True)
    reaper = threading.Thread(target=process.wait, daemon=True)
    reaper.start()
    try:
        yield process
    finally:
        if process.poll() is None:
            process.terminate()
        reaper.join(timeout=5)
        if reaper.is_alive():
            raise RuntimeError(f"Owned test process {process.pid} did not terminate.")
        if process.stdout is not None:
            process.stdout.close()
