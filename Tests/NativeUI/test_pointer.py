import ctypes as C
import unittest
from unittest.mock import Mock, call, patch

from accessibility import AXPair
from pointer import Pointer, Rect


class PointerSafetyTests(unittest.TestCase):
    def pointer(self, pid=123, error=0):
        pointer = object.__new__(Pointer)
        pointer.root = 1
        pointer.release = Mock()
        pointer.create = Mock()
        pointer.post = Mock()
        pointer.flags = Mock()
        pointer.read_position = Mock(return_value=AXPair(10, 20))
        pointer.screens = [Rect(AXPair(0, 0), AXPair(1710, 1107))]

        def at_point(_root, _x, _y, result):
            C.cast(result, C.POINTER(C.c_void_p))[0] = 99
            return error

        def get_pid(_element, result):
            C.cast(result, C.POINTER(C.c_int))[0] = pid
            return 0

        pointer.at_point = at_point
        pointer.get_pid = get_pid
        return pointer

    def test_clicking_another_process_is_blocked(self):
        pointer = self.pointer(pid=456)
        with self.assertRaisesRegex(RuntimeError, "Click blocked"):
            pointer.click(123, 10, 20)
        pointer.create.assert_not_called()
        pointer.post.assert_not_called()
        pointer.release.assert_called_once_with(99)

    def test_transport_error_never_allows_a_click(self):
        pointer = self.pointer(error=-25204)
        with self.assertRaisesRegex(RuntimeError, "hit-test failed"):
            pointer.click(123, 10, 20)
        pointer.post.assert_not_called()

    def test_owned_target_passes(self):
        pointer = self.pointer()
        pointer.require_target(123, 10, 20)
        pointer.release.assert_called_once_with(99)

    def test_invalid_coordinates_are_rejected(self):
        pointer = self.pointer()
        with self.assertRaisesRegex(RuntimeError, "Invalid owned"):
            pointer.click(123, float("nan"), 20)
        pointer.post.assert_not_called()

    def test_right_click_uses_a_complete_right_button_pair(self):
        pointer = self.pointer()
        pointer.create.side_effect = [10, 11, 12]
        pointer.click(123, 10, 20, right=True)
        self.assertEqual([entry.args[1] for entry in pointer.create.call_args_list], [5, 3, 4])
        self.assertEqual([entry.args[3] for entry in pointer.create.call_args_list], [0, 1, 1])
        self.assertEqual(pointer.post.call_args_list, [call(0, 10), call(0, 11), call(0, 12)])

    def test_control_click_preserves_the_left_button_and_modifier(self):
        pointer = self.pointer()
        pointer.create.side_effect = [10, 11, 12]
        pointer.click(123, 10, 20, control=True)
        self.assertEqual([entry.args[1] for entry in pointer.create.call_args_list], [5, 1, 2])
        self.assertEqual(pointer.flags.call_args_list, [call(10, 0), call(11, 1 << 18), call(12, 1 << 18)])

    def test_interruption_still_releases_the_mouse_button(self):
        pointer = self.pointer()
        pointer.create.side_effect = [10, 11, 12]
        with patch("pointer.time.sleep", side_effect=[None, KeyboardInterrupt]):
            with self.assertRaises(KeyboardInterrupt):
                pointer.click(123, 10, 20)
        self.assertEqual(pointer.post.call_args_list, [call(0, 10), call(0, 11), call(0, 12)])
        self.assertEqual(pointer.release.call_args_list, [call(99), call(99), call(10), call(11), call(12)])

    def test_undelivered_motion_never_sends_a_click(self):
        pointer = self.pointer()
        pointer.create.side_effect = [10, 11, 12]
        pointer.read_position.return_value = AXPair(0, 0)
        with patch("pointer.time.monotonic", side_effect=[0, 2]):
            with self.assertRaisesRegex(RuntimeError, "no click was sent"):
                pointer.click(123, 10, 20)
        self.assertEqual(pointer.post.call_args_list, [call(0, 10)])

    def test_target_is_rechecked_after_motion(self):
        pointer = self.pointer()
        pointer.create.side_effect = [10, 11, 12]
        pointer.require_target = Mock(side_effect=[None, RuntimeError("Target changed")])
        with self.assertRaisesRegex(RuntimeError, "Target changed"):
            pointer.click(123, 10, 20)
        self.assertEqual(pointer.post.call_args_list, [call(0, 10)])

    def proxy_target(self, role="AXMenuBar", owner=123):
        pointer = self.pointer(pid=456)

        def get_pid(element, result):
            C.cast(result, C.POINTER(C.c_int))[0] = owner if element == 101 else 456
            return 0

        pointer.get_pid = get_pid
        session = Mock()
        session.string_value.return_value = role
        session.bounds.side_effect = lambda row: (
            (1017, 5, 98, 24) if row["element"] == 101 else (0, 0, 1710, 34)
        )
        row = {"element": 101, "AXRole": "AXMenuBarItem", "AXDescription": "CPU 使用率"}
        return pointer, (session, row)

    def test_system_menu_container_requires_the_owned_logical_item(self):
        pointer, item = self.proxy_target()
        pointer.require_target(123, 1066, 17, status_item=item)

    def test_menu_container_does_not_allow_clicking_other_status_items(self):
        pointer, item = self.proxy_target()
        with self.assertRaisesRegex(RuntimeError, "Click blocked"):
            pointer.require_target(123, 1200, 17, status_item=item)

    def test_proxy_cannot_override_a_foreign_window_or_item_owner(self):
        for role, owner in (("AXWindow", 123), ("AXMenuBar", 456)):
            pointer, item = self.proxy_target(role, owner)
            with self.assertRaisesRegex(RuntimeError, "Click blocked"):
                pointer.require_target(123, 1066, 17, status_item=item)

    def test_initial_offscreen_status_item_is_not_ready(self):
        pointer = self.pointer()
        self.assertFalse(pointer.on_screen((7, 1103, 98, 30)))
        self.assertTrue(pointer.on_screen((1017, 5, 98, 24)))
