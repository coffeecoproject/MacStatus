import unittest
from unittest.mock import Mock

from fixtures import rows_with_panels
from panel_checks import (
    live_disk_is_present, live_memory_is_present, live_temperature_is_present, live_values_match,
    assert_compact_content, assert_compact_layout
)


def memory_rows(amount="内存已用 6.5 GiB，总量 8 GiB", pressure="内存压力：警告"):
    rows = rows_with_panels(1)
    rows.extend([
        {"AXRole": "AXStaticText", "AXValue": "CPU 使用率 50%"},
        {"AXRole": "AXStaticText", "AXValue": amount},
        {"AXRole": "AXStaticText", "AXValue": pressure}
    ])
    for row in rows:
        row.setdefault("AXValue", "")
    return rows


def disk_rows(amount="硬盘已用 330 GiB，总量 500 GiB"):
    rows = memory_rows()
    rows.append({"AXRole": "AXStaticText", "AXValue": amount})
    return rows


class MemoryPanelTests(unittest.TestCase):
    def test_memory_usage_requires_an_explicit_pressure_state(self):
        self.assertTrue(live_memory_is_present(memory_rows()))
        self.assertFalse(live_memory_is_present(memory_rows(pressure="")))

    def test_unavailable_pressure_can_coexist_with_live_usage(self):
        self.assertTrue(live_memory_is_present(memory_rows(pressure="内存压力：不可用")))

    def test_invalid_memory_amount_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "Invalid displayed memory"):
            live_memory_is_present(memory_rows(amount="内存已用 9.0 GiB，总量 8 GiB"))

    def test_warming_up_does_not_count_as_a_live_reading(self):
        self.assertFalse(live_memory_is_present(memory_rows(amount="内存正在采样")))

    def test_live_readings_do_not_require_explanations_or_timestamps(self):
        rows = memory_rows()
        self.assertTrue(live_values_match(rows))
        self.assertTrue(live_memory_is_present(rows))
        assert_compact_content(rows)


class DiskPanelTests(unittest.TestCase):
    def test_disk_usage_is_present_as_used_and_total_capacity(self):
        self.assertTrue(live_disk_is_present(disk_rows()))

    def test_invalid_disk_amount_is_rejected(self):
        with self.assertRaisesRegex(AssertionError, "Invalid displayed disk"):
            live_disk_is_present(disk_rows(amount="硬盘已用 600 GiB，总量 500 GiB"))

    def test_warming_up_does_not_count_as_a_live_disk_reading(self):
        self.assertFalse(live_disk_is_present(disk_rows(amount="硬盘 采样中")))


class CompactPanelTests(unittest.TestCase):
    def test_old_helper_copy_is_rejected(self):
        for text in ("CPU 更新于 21:00:03", "实时使用率", "不含可回收文件缓存", "MacStatus"):
            with self.subTest(text=text):
                rows = memory_rows()
                rows.append({"AXRole": "AXStaticText", "AXValue": text})
                with self.assertRaisesRegex(AssertionError, "Redundant copy"):
                    assert_compact_content(rows)

    def test_application_identity_is_not_panel_branding(self):
        rows = memory_rows()
        rows[0]["AXTitle"] = "MacStatus"
        assert_compact_content(rows)

    def test_panel_close_and_quit_controls_are_rejected(self):
        for description in ("退出 MacStatus", "关闭"):
            rows = memory_rows()
            rows.append({"AXRole": "AXButton", "AXDescription": description, "AXValue": ""})
            with self.assertRaisesRegex(AssertionError, "must not contain"):
                assert_compact_content(rows)

    def layout_rows(self):
        rows = disk_rows()
        rows.append({"AXRole": "AXStaticText", "AXValue": "CPU 温度 67°C"})
        return rows

    def test_large_panel_is_rejected(self):
        session = Mock()
        session.bounds.return_value = (0, 0, 346, 488)
        with self.assertRaisesRegex(AssertionError, "no longer compact"):
            assert_compact_layout(session, self.layout_rows())

    def test_clipped_metric_is_rejected(self):
        session = Mock()
        session.bounds.side_effect = [(0, 0, 306, 260), (200, 0, 200, 30)]
        with self.assertRaisesRegex(AssertionError, "clipped"):
            assert_compact_layout(session, self.layout_rows())

    def test_compact_unclipped_layout_passes(self):
        session = Mock()
        session.bounds.side_effect = [
            (0, 0, 306, 280), (200, 10, 70, 30), (120, 120, 150, 24),
            (120, 170, 150, 24), (200, 60, 70, 24)
        ]
        assert_compact_layout(session, self.layout_rows())

    def test_missing_temperature_is_not_hidden_by_a_duplicate_cpu_value(self):
        rows = self.layout_rows()
        next(row for row in rows if row["AXValue"] == "CPU 温度 67°C")["AXValue"] = "CPU 使用率 50%"
        session = Mock()
        session.bounds.return_value = (0, 0, 306, 230)
        with self.assertRaisesRegex(AssertionError, "exactly one metric"):
            assert_compact_layout(session, rows)


class TemperaturePanelTests(unittest.TestCase):
    def rows(self, value):
        rows = disk_rows()
        rows.append({"AXRole": "AXStaticText", "AXValue": value})
        return rows

    def test_temperature_requires_an_explicit_celsius_reading(self):
        self.assertTrue(live_temperature_is_present(self.rows("CPU 温度 67°C")))
        for value in ("CPU 温度 采样中", "CPU 温度 不可用", "CPU 温度 —", "67", "电池温度 30°C"):
            with self.subTest(value=value):
                self.assertFalse(live_temperature_is_present(self.rows(value)))

    def test_implausible_values_are_rejected(self):
        for value in ("CPU 温度 -10°C", "CPU 温度 300°C"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(AssertionError, "Invalid displayed CPU temperature"):
                    live_temperature_is_present(self.rows(value))
