"""Read and operate on one application's accessibility tree without permission prompts."""

import ctypes as C


ATTRIBUTE_UNSUPPORTED = -25205
NO_VALUE = -25212
CANNOT_COMPLETE = -25204


class AXPair(C.Structure):
    _fields_ = [("x", C.c_double), ("y", C.c_double)]


class AXReadError(RuntimeError):
    def __init__(self, attribute, code):
        super().__init__(f"Accessibility read failed: {attribute}, AX error {code}")
        self.attribute = attribute
        self.code = code


def bind(library, name, arguments, result):
    function = getattr(library, name)
    function.argtypes = arguments
    function.restype = result
    return function


class Accessibility:
    def __init__(self, pid):
        ax = C.CDLL(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        )
        cf = C.CDLL(
            "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
        )
        pointer = C.c_void_p
        trusted = bind(ax, "AXIsProcessTrusted", [], C.c_bool)
        if not trusted():
            raise RuntimeError("Accessibility is not authorized; permissions were not changed.")
        create = bind(ax, "AXUIElementCreateApplication", [C.c_int], pointer)
        self.copy = bind(
            ax, "AXUIElementCopyAttributeValue",
            [pointer, pointer, C.POINTER(pointer)], C.c_int
        )
        self.perform = bind(ax, "AXUIElementPerformAction", [pointer, pointer], C.c_int)
        self.get_value = bind(ax, "AXValueGetValue", [pointer, C.c_int, pointer], C.c_bool)
        self.string = bind(
            cf, "CFStringCreateWithCString",
            [pointer, C.c_char_p, C.c_uint32], pointer
        )
        self.text = bind(
            cf, "CFStringGetCString",
            [pointer, pointer, C.c_long, C.c_uint32], C.c_bool
        )
        self.type_id = bind(cf, "CFGetTypeID", [pointer], C.c_ulong)
        self.string_id = bind(cf, "CFStringGetTypeID", [], C.c_ulong)()
        self.array_id = bind(cf, "CFArrayGetTypeID", [], C.c_ulong)()
        self.boolean_id = bind(cf, "CFBooleanGetTypeID", [], C.c_ulong)()
        self.boolean = bind(cf, "CFBooleanGetValue", [pointer], C.c_bool)
        self.count = bind(cf, "CFArrayGetCount", [pointer], C.c_long)
        self.item = bind(cf, "CFArrayGetValueAtIndex", [pointer, C.c_long], pointer)
        self.release = bind(cf, "CFRelease", [pointer], None)
        self.root = create(pid)
        if not self.root:
            raise RuntimeError("Could not create an application accessibility handle.")
        self.owned = []

    def attribute(self, element, name, *, optional=False):
        key = self.string(None, name.encode(), 0x08000100)
        result = C.c_void_p()
        try:
            code = self.copy(element, key, C.byref(result))
        finally:
            self.release(key)
        if code:
            if optional and code in (ATTRIBUTE_UNSUPPORTED, NO_VALUE):
                return None
            raise AXReadError(name, code)
        if not result.value:
            raise RuntimeError(f"Accessibility returned success without a value: {name}")
        self.owned.append(result.value)
        return result.value

    def string_value(self, value):
        if value is None:
            return ""
        if self.type_id(value) != self.string_id:
            raise RuntimeError("Expected accessibility text, received a different value type.")
        buffer = C.create_string_buffer(4096)
        if not self.text(value, buffer, len(buffer), 0x08000100):
            raise RuntimeError("Could not decode accessibility text.")
        return buffer.value.decode()

    def clear_snapshot(self):
        for value in reversed(self.owned):
            self.release(value)
        self.owned.clear()

    def snapshot(self):
        self.clear_snapshot()
        rows = []

        def walk(element, depth):
            row = {
                "element": element,
                "AXRole": self.string_value(self.attribute(element, "AXRole"))
            }
            for name in ("AXTitle", "AXDescription", "AXValue"):
                row[name] = self.string_value(self.attribute(element, name, optional=True))
            if depth == 0:
                frontmost = self.attribute(element, "AXFrontmost")
                if self.type_id(frontmost) != self.boolean_id:
                    raise RuntimeError("Invalid application focus state.")
                row["AXFrontmost"] = self.boolean(frontmost)
            rows.append(row)

            children = self.attribute(element, "AXChildren", optional=True)
            if children is None:
                return
            if self.type_id(children) != self.array_id:
                raise RuntimeError("Invalid accessibility children array.")
            count = self.count(children)
            if depth >= 10 and count:
                raise RuntimeError("Accessibility tree exceeded the expected depth.")
            for index in range(count):
                walk(self.item(children, index), depth + 1)

        walk(self.root, 0)
        if rows[0]["AXRole"] != "AXApplication":
            raise RuntimeError("The accessibility root is not an application.")
        return rows

    def press(self, row, *, may_terminate=False):
        action = self.string(None, b"AXPress", 0x08000100)
        try:
            code = self.perform(row["element"], action)
        finally:
            self.release(action)
        # Quit may close the AX connection before returning. The caller must
        # separately confirm process exit, rather than treating this as success.
        if code and not (may_terminate and code == CANNOT_COMPLETE):
            raise RuntimeError(f"AXPress failed: {code}")

    def bounds(self, row):
        point, size = AXPair(), AXPair()
        position = self.attribute(row["element"], "AXPosition")
        dimensions = self.attribute(row["element"], "AXSize")
        if not self.get_value(position, 1, C.byref(point)):
            raise RuntimeError("Could not decode accessibility position.")
        if not self.get_value(dimensions, 2, C.byref(size)):
            raise RuntimeError("Could not decode accessibility size.")
        return point.x, point.y, size.x, size.y

    def close(self):
        self.clear_snapshot()
        self.release(self.root)
