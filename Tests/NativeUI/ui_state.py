"""Accessibility state assertions; transport failures are never treated as closed UI."""

import time


def menu_item(rows, *, required=True):
    items = [
        row for row in rows
        if row["AXRole"] == "AXMenuBarItem" and row["AXDescription"] == "CPU 使用率"
    ]
    if len(items) > 1:
        raise AssertionError("Duplicate CPU menu bar items.")
    if not items:
        if required:
            raise AssertionError("CPU menu bar item is missing; cannot determine panel state.")
        return None
    return items[0]


def panel_visible(rows):
    menu_item(rows)
    count = sum(row["AXRole"] == "AXPopover" for row in rows)
    if count > 1:
        raise AssertionError("Duplicate CPU panels.")
    return count == 1


def exit_item(rows, *, required=True):
    menu_item(rows)
    items = [
        row for row in rows
        if row["AXRole"] == "AXMenuItem" and row["AXTitle"] == "退出 MacStatus"
    ]
    if len(items) > 1:
        raise AssertionError("Duplicate Quit menu items.")
    if not items:
        if required:
            raise AssertionError("Quit menu item is missing.")
        return None
    if panel_visible(rows):
        raise AssertionError("Exit menu and metric panel must not be open together.")
    return items[0]


def summary(rows):
    item = menu_item(rows, required=False)
    return (
        f"observed_at={time.monotonic():.3f}, "
        f"app_active={rows[0].get('AXFrontmost') if rows else None}, "
        f"popovers={sum(row['AXRole'] == 'AXPopover' for row in rows)}, "
        f"menu={item['AXTitle'] if item else 'missing'}"
    )


def wait_for_snapshot(session, description, condition, *, timeout=4):
    deadline = time.monotonic() + timeout
    rows = []
    while time.monotonic() < deadline:
        rows = session.snapshot()
        if condition(rows):
            return rows
        time.sleep(0.1)
    raise AssertionError(f"{description}: timed out; {summary(rows)}")


def require_open(rows):
    if not panel_visible(rows):
        raise AssertionError(f"Panel closed during an open-panel check; {summary(rows)}")
