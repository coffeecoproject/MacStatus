"""Mouse events guarded by an accessibility hit-test against the owned target PID."""

import ctypes as C
import math
import time

from accessibility import AXPair, bind


class Rect(C.Structure):
    _fields_ = [("origin", AXPair), ("size", AXPair)]


def contains(bounds, x, y):
    left, top, width, height = bounds
    return width > 0 and height > 0 and left <= x < left + width and top <= y < top + height


class Pointer:
    def __init__(self):
        ax = C.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        cg = C.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        cf = C.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        pointer = C.c_void_p
        if not bind(ax, "AXIsProcessTrusted", [], C.c_bool)():
            raise RuntimeError("Mouse automation requires existing accessibility permission.")
        if not bind(cg, "CGPreflightPostEventAccess", [], C.c_bool)():
            raise RuntimeError("Mouse events are not authorized; permissions were not changed.")
        self.root = bind(ax, "AXUIElementCreateSystemWide", [], pointer)()
        if not self.root:
            raise RuntimeError("Could not create the system accessibility handle.")
        self.at_point = bind(
            ax, "AXUIElementCopyElementAtPosition",
            [pointer, C.c_float, C.c_float, C.POINTER(pointer)], C.c_int
        )
        self.get_pid = bind(ax, "AXUIElementGetPid", [pointer, C.POINTER(C.c_int)], C.c_int)
        self.create = bind(cg, "CGEventCreateMouseEvent", [pointer, C.c_uint32, AXPair, C.c_uint32], pointer)
        self.flags = bind(cg, "CGEventSetFlags", [pointer, C.c_uint64], None)
        self.post = bind(cg, "CGEventPost", [C.c_uint32, pointer], None)
        self.current_event = bind(cg, "CGEventCreate", [pointer], pointer)
        self.location = bind(cg, "CGEventGetLocation", [pointer], AXPair)
        self.release = bind(cf, "CFRelease", [pointer], None)
        display_count = C.c_uint32()
        displays = bind(
            cg, "CGGetActiveDisplayList",
            [C.c_uint32, C.POINTER(C.c_uint32), C.POINTER(C.c_uint32)], C.c_int
        )
        bounds = bind(cg, "CGDisplayBounds", [C.c_uint32], Rect)
        if displays(0, None, C.byref(display_count)):
            raise RuntimeError("Could not read display geometry.")
        ids = (C.c_uint32 * display_count.value)()
        if displays(display_count.value, ids, C.byref(display_count)):
            raise RuntimeError("Could not enumerate display geometry.")
        self.screens = [bounds(identifier) for identifier in ids]

    def on_screen(self, bounds):
        x, y, width, height = bounds
        return width > 0 and height > 0 and any(
            screen.origin.x <= x and screen.origin.y <= y
            and x + width <= screen.origin.x + screen.size.x
            and y + height <= screen.origin.y + screen.size.y
            for screen in self.screens
        )

    def is_owned_status_item(self, pid, x, y, hit, status_item):
        if status_item is None:
            return False
        session, row = status_item
        if row["AXRole"] != "AXMenuBarItem" or row["AXDescription"] != "CPU 使用率":
            return False
        owner = C.c_int()
        if self.get_pid(row["element"], C.byref(owner)) or owner.value != pid:
            return False
        # macOS 26 hit-tests status items as the foreground app's entire menu bar.
        # Accept that container only with the test app's own AX item and geometry.
        role = session.string_value(session.attribute(hit, "AXRole"))
        return (
            role == "AXMenuBar"
            and self.on_screen(session.bounds(row))
            and contains(session.bounds(row), x, y)
            and contains(session.bounds({"element": hit}), x, y)
        )

    def require_target(self, pid, x, y, *, status_item=None):
        if pid <= 0 or not (math.isfinite(x) and math.isfinite(y)):
            raise RuntimeError("Invalid owned click target.")
        element = C.c_void_p()
        code = self.at_point(self.root, x, y, C.byref(element))
        if code or not element.value:
            if element.value:
                self.release(element.value)
            raise RuntimeError(f"Click hit-test failed: {code}")
        try:
            actual = C.c_int()
            code = self.get_pid(element, C.byref(actual))
            if code or (
                actual.value != pid
                and not self.is_owned_status_item(pid, x, y, element.value, status_item)
            ):
                raise RuntimeError(f"Click blocked: expected owned PID {pid}, hit {actual.value}, AX error {code}")
        finally:
            self.release(element.value)

    def click(self, pid, x, y, *, right=False, control=False, status_item=None):
        self.require_target(pid, x, y, status_item=status_item)
        button, event_types = (1, (3, 4)) if right else (0, (1, 2))
        events = []
        try:
            for event_type in (5,) + event_types:
                event = self.create(None, event_type, AXPair(x, y), 0 if event_type == 5 else button)
                if not event:
                    raise RuntimeError("Could not construct mouse event.")
                events.append(event)
                self.flags(event, (1 << 18) if control and event_type != 5 else 0)
            self.post(0, events[0])
            deadline = time.monotonic() + 1
            while True:
                point = self.read_position()
                if abs(point.x - x) < 1 and abs(point.y - y) < 1:
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError("Mouse movement was not delivered; no click was sent.")
                time.sleep(0.02)
            time.sleep(0.1)
            self.require_target(pid, x, y, status_item=status_item)
            self.post(0, events[1])
            try:
                time.sleep(0.05)
            finally:
                self.post(0, events[2])
        finally:
            for event in events:
                self.release(event)

    def read_position(self):
        event = self.current_event(None)
        if not event:
            raise RuntimeError("Could not read pointer position.")
        try:
            return self.location(event)
        finally:
            self.release(event)

    def close(self):
        self.release(self.root)
