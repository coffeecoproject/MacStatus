"""Content and geometry checks for the read-only metrics panel."""

import re

from ui_state import menu_item, require_open


def live_values_match(rows):
    require_open(rows)
    item = menu_item(rows)
    if not re.fullmatch(r" CPU (?:100|\d{1,2})%", item["AXTitle"]):
        return False
    return any(
        row["AXRole"] == "AXStaticText" and row["AXValue"] == item["AXValue"]
        for row in rows
    )


def live_memory_is_present(rows):
    require_open(rows)
    readings = [
        re.fullmatch(r"内存已用 (\d+(?:\.\d+)?) GiB，总量 (\d+(?:\.\d+)?) GiB", row["AXValue"])
        for row in rows if row["AXRole"] == "AXStaticText"
    ]
    reading = next((match for match in readings if match), None)
    if reading is None:
        return False
    used, total = map(float, reading.groups())
    if not 0 <= used <= total or total <= 0:
        raise AssertionError(f"Invalid displayed memory usage: {reading.group(0)}")
    return any(
        row["AXValue"] in (
            "内存压力：正常", "内存压力：警告", "内存压力：严重", "内存压力：不可用"
        )
        for row in rows
    )


def live_disk_is_present(rows):
    require_open(rows)
    readings = [
        re.fullmatch(r"硬盘已用 (\d+(?:\.\d+)?) GiB，总量 (\d+(?:\.\d+)?) GiB", row["AXValue"])
        for row in rows if row["AXRole"] == "AXStaticText"
    ]
    reading = next((match for match in readings if match), None)
    if reading is None:
        return False
    used, total = map(float, reading.groups())
    if not 0 <= used <= total or total <= 0:
        raise AssertionError(f"Invalid displayed disk usage: {reading.group(0)}")
    return True


def live_temperature_is_present(rows):
    require_open(rows)
    for row in rows:
        if row["AXRole"] != "AXStaticText":
            continue
        reading = re.fullmatch(r"CPU 温度 (-?\d+(?:\.\d+)?)°C", row["AXValue"])
        if reading:
            # Raw readings are validated before whole-degree rounding.
            if not 0 <= float(reading.group(1)) <= 150:
                raise AssertionError(f"Invalid displayed CPU temperature: {reading.group(0)}")
            return True
    return False


def assert_compact_content(rows):
    require_open(rows)
    unwanted = (
        "更新于", "上次成功", "实时使用率", "实时用量", "自动重试",
        "需要两次采样", "所有 CPU 核心", "文件缓存", "二进制容量"
    )
    for row in rows:
        if row["AXRole"] == "AXButton":
            raise AssertionError("The metric panel must not contain Close or Quit buttons.")
        if row["AXRole"] != "AXStaticText":
            continue
        text = row["AXValue"]
        if text == "MacStatus" or any(fragment in text for fragment in unwanted):
            raise AssertionError(f"Redundant copy remains in the compact panel: {text}")


def assert_compact_layout(session, rows):
    require_open(rows)
    assert_compact_content(rows)
    popover = next(row for row in rows if row["AXRole"] == "AXPopover")
    panel = session.bounds(popover)
    if panel[2] > 320 or panel[3] > 300:
        raise AssertionError(f"Panel is no longer compact: {panel[2:]} pt")
    values = []
    for prefix in ("CPU 使用率 ", "内存已用 ", "硬盘已用 ", "CPU 温度 "):
        matches = [
            row for row in rows
            if row["AXRole"] == "AXStaticText" and row["AXValue"].startswith(prefix)
        ]
        if len(matches) != 1:
            raise AssertionError(f"Expected exactly one metric value: {prefix}")
        values.extend(matches)
    for row in values:
        x, y, width, height = session.bounds(row)
        if not (
            width > 0 and height > 0
            and panel[0] - 1 <= x and panel[1] - 1 <= y
            and x + width <= panel[0] + panel[2] + 1
            and y + height <= panel[1] + panel[3] + 1
        ):
            raise AssertionError("A metric is clipped outside the panel.")
