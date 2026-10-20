"""Launch, check and exit only our test instance; no installation or permission changes."""

import argparse
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

from owned_process import owned_process
from pointer import Pointer
from smoke import run


class OutsideTarget:
    def __init__(self, process):
        self.pid = process.pid
        self.events = queue.Queue()
        self.history = []
        self.reader = threading.Thread(target=self.read_events, args=(process.stdout,), daemon=True)
        self.reader.start()
        ready = self.wait_for("ready")
        self.x, self.y = ready["x"], ready["y"]

    def read_events(self, stream):
        for line in stream:
            try:
                event = json.loads(line)
            except ValueError:
                event = {"event": "invalid-output", "line": line}
            self.history.append(event)
            self.events.put(event)

    def wait_for(self, name):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                event = self.events.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if event["event"] == name:
                return event
            if event["event"] == "invalid-output":
                raise RuntimeError(f"Invalid fixture output: {event}")
        raise RuntimeError(f"Outside-click fixture did not acknowledge {name}.")

    def click(self, pointer):
        pointer.click(self.pid, self.x, self.y)
        # Native menus may consume a dismissal click instead of forwarding it.
        # The workflow checks that the appropriate UI actually closes.


def main(app):
    root = Path(__file__).resolve().parents[2]
    app = app.resolve()
    executable = app / "Contents/MacOS/MacStatus"
    if app.name != "MacStatus.app" or not executable.is_file():
        raise RuntimeError("Expected a packaged MacStatus.app.")
    existing = subprocess.run(["/usr/bin/pgrep", "-x", "MacStatus"], capture_output=True)
    if existing.returncode != 1:
        raise RuntimeError("Existing instance or process lookup error; no apps were changed.")

    build = root / ".build/native-ui"
    build.mkdir(parents=True, exist_ok=True)
    for helper in ("OutsideClickTarget", "WaitForLaunch"):
        subprocess.run([
            "/usr/bin/swiftc", "-swift-version", "6", "-warnings-as-errors",
            str(Path(__file__).with_name(helper + ".swift")), "-o", str(build / helper)
        ], check=True, capture_output=True, text=True)

    output = io.StringIO()
    outside = None
    pointer = Pointer()
    try:
        with tempfile.TemporaryFile(mode="w+t", dir=build) as diagnostics:
            try:
                with owned_process(
                    [str(build / "OutsideClickTarget")], stdout=subprocess.PIPE, stderr=diagnostics
                ) as fixture:
                    outside = OutsideTarget(fixture)
                    with owned_process([str(executable)], stdout=diagnostics, stderr=diagnostics) as process:
                        subprocess.run(
                            [str(build / "WaitForLaunch"), str(process.pid)],
                            check=True, stdout=diagnostics, stderr=diagnostics, timeout=10
                        )
                        with redirect_stdout(output):
                            run(process.pid, pointer, outside)
                        if process.wait(timeout=5) != 0:
                            raise RuntimeError("App did not quit cleanly.")
            finally:
                diagnostics.seek(0)
                detail = diagnostics.read()
                if detail:
                    output.write(detail)
    except BaseException:
        if outside is not None:
            output.write(f"Fixture events (PID {outside.pid}): {outside.history}\n")
        raise
    finally:
        pointer.close()
        print(output.getvalue(), end="")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        main(arguments.app)
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr)
        raise
