"""Interaction checks for an owned instance. Launch via run_owned.py."""

import os
import time

from accessibility import Accessibility
from panel_checks import (
    live_values_match, live_memory_is_present, live_temperature_is_present,
    assert_compact_content, assert_compact_layout
)
from ui_state import menu_item, panel_visible, exit_item, wait_for_snapshot


def process_exists(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def run(pid, pointer, outside):
    session = Accessibility(pid)
    try:
        rows = wait_for_snapshot(
            session, "Initial menu bar",
            lambda rows: menu_item(rows, required=False) is not None
        )
        if panel_visible(rows):
            raise AssertionError("A fresh launch must not open the panel automatically.")
        print("PASS: fresh launch shows only the menu bar item")

        def click_icon(*, right=False, control=False):
            current = wait_for_snapshot(
                session, "Status item placement",
                lambda rows: pointer.on_screen(session.bounds(menu_item(rows)))
            )
            bounds = session.bounds(menu_item(current))
            pointer.click(
                pid, bounds[0] + bounds[2] / 2, bounds[1] + bounds[3] / 2,
                right=right, control=control, status_item=(session, menu_item(current))
            )

        started = time.monotonic()
        click_icon()
        wait_for_snapshot(session, "First left-click opening", panel_visible)
        print(f"PASS: first left-click opening ({time.monotonic() - started:.2f}s)")
        for name, condition in (
            ("CPU menu/panel agreement", live_values_match),
            ("Memory and pressure", live_memory_is_present),
            ("CPU temperature", live_temperature_is_present)
        ):
            rows = wait_for_snapshot(session, name, condition, timeout=7)
            print(f"PASS: {name}")
        assert_compact_layout(session, rows)
        panel = session.bounds(next(row for row in rows if row["AXRole"] == "AXPopover"))
        print(f"PASS: compact panel {panel[2]:g} × {panel[3]:g} pt, no Close/Quit buttons")

        # Do not force numerical changes or reopen a panel after unexpected dismissal.
        for _ in range(12):
            time.sleep(1)
            rows = wait_for_snapshot(
                session, "Readings remain visible",
                lambda rows: (
                    live_values_match(rows) and live_memory_is_present(rows)
                    and live_temperature_is_present(rows)
                )
            )
            assert_compact_content(rows)
        print("PASS: readings remain visible beyond the freshness deadline")

        outside.click(pointer)
        rows = wait_for_snapshot(session, "Outside-click dismissal", lambda rows: not panel_visible(rows))
        if not process_exists(pid):
            raise AssertionError("Dismissing the panel must not stop the app.")
        print("PASS: outside click dismisses the panel without stopping the app")

        for index in range(2):
            click_icon()
            wait_for_snapshot(session, f"Reopen #{index + 1}", panel_visible)
            click_icon()
            wait_for_snapshot(session, f"Toggle closed #{index + 1}", lambda rows: not panel_visible(rows))
        print("PASS: repeated left-click toggling")

        # Exercise right-click both while closed and while the popover is open.
        for opened, control in ((False, False), (True, False), (False, True)):
            if opened:
                click_icon()
                wait_for_snapshot(session, "Panel before right-click", panel_visible)
            click_icon(right=not control, control=control)
            wait_for_snapshot(
                session, "Exit context menu",
                lambda rows: exit_item(rows, required=False) is not None
            )
            outside.click(pointer)
            wait_for_snapshot(
                session, "Context menu cancellation",
                lambda rows: exit_item(rows, required=False) is None and not panel_visible(rows)
            )
            if not process_exists(pid):
                raise AssertionError("Cancelling the exit menu must not stop the app.")
        print("PASS: right-click/Control-click menu, mutual exclusion, cancellation")

        click_icon()
        wait_for_snapshot(session, "Left-click still opens after context menu", panel_visible)
        click_icon(right=True)
        rows = wait_for_snapshot(
            session, "Final exit menu",
            lambda rows: exit_item(rows, required=False) is not None
        )
        session.press(exit_item(rows), may_terminate=True)
        deadline = time.monotonic() + 4
        while process_exists(pid):
            if time.monotonic() >= deadline:
                raise AssertionError("Quit menu action did not terminate the app.")
            time.sleep(0.1)
        print("PASS: right-click → Quit terminates the app")
    finally:
        session.close()
