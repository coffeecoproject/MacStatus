import unittest
from unittest.mock import Mock

from accessibility import AXReadError, CANNOT_COMPLETE
from fixtures import rows_with_panels
from ui_state import panel_visible, require_open, wait_for_snapshot, summary, exit_item


class PanelStateTests(unittest.TestCase):
    def test_a_valid_tree_can_prove_the_panel_is_closed(self):
        self.assertFalse(panel_visible(rows_with_panels(0)))

    def test_a_single_popover_is_open(self):
        self.assertTrue(panel_visible(rows_with_panels(1)))

    def test_missing_tree_or_menu_is_not_a_closed_panel(self):
        for rows in ([], [{"AXRole": "AXApplication"}]):
            with self.subTest(rows=rows):
                with self.assertRaisesRegex(AssertionError, "menu bar item is missing"):
                    panel_visible(rows)

    def test_duplicate_panels_fail(self):
        with self.assertRaisesRegex(AssertionError, "Duplicate CPU panels"):
            panel_visible(rows_with_panels(2))

    def test_unexpected_dismissal_reports_focus(self):
        rows = rows_with_panels(0)
        rows[0]["AXFrontmost"] = False
        with self.assertRaisesRegex(AssertionError, "app_active=False"):
            require_open(rows)

    def test_read_errors_propagate_instead_of_satisfying_close_checks(self):
        session = Mock()
        session.snapshot.side_effect = AXReadError("AXChildren", CANNOT_COMPLETE)
        with self.assertRaises(AXReadError):
            wait_for_snapshot(session, "Close panel", lambda rows: not panel_visible(rows))
        session.snapshot.assert_called_once()

    def test_diagnostics_include_focus_and_menu_data(self):
        result = summary(rows_with_panels(1))
        self.assertIn("app_active=True", result)
        self.assertIn("popovers=1", result)
        self.assertIn("CPU 50%", result)


class ExitMenuTests(unittest.TestCase):
    def menu_rows(self, panels=0):
        return rows_with_panels(panels) + [
            {"AXRole": "AXMenu", "AXTitle": ""},
            {"AXRole": "AXMenuItem", "AXTitle": "退出 MacStatus"}
        ]

    def test_native_exit_menu_item_is_required(self):
        self.assertEqual(exit_item(self.menu_rows())["AXRole"], "AXMenuItem")
        with self.assertRaisesRegex(AssertionError, "missing"):
            exit_item(rows_with_panels(0))

    def test_missing_menu_is_distinct_from_read_failure(self):
        self.assertIsNone(exit_item(rows_with_panels(0), required=False))
        with self.assertRaisesRegex(AssertionError, "menu bar item is missing"):
            exit_item([], required=False)

    def test_exit_menu_must_replace_the_panel(self):
        with self.assertRaisesRegex(AssertionError, "must not be open together"):
            exit_item(self.menu_rows(panels=1))

    def test_duplicate_quit_items_fail(self):
        rows = self.menu_rows()
        rows.append({"AXRole": "AXMenuItem", "AXTitle": "退出 MacStatus"})
        with self.assertRaisesRegex(AssertionError, "Duplicate"):
            exit_item(rows)
