import ctypes as C
import unittest
from unittest.mock import Mock

from accessibility import (
    Accessibility, AXReadError, ATTRIBUTE_UNSUPPORTED, NO_VALUE, CANNOT_COMPLETE
)


class AttributeReadTests(unittest.TestCase):
    def session_with_result(self, code, value=None):
        session = object.__new__(Accessibility)
        session.owned = []
        session.string = Mock(return_value=1)
        session.release = Mock()

        def copy(_element, _key, result):
            C.cast(result, C.POINTER(C.c_void_p))[0] = value
            return code

        session.copy = copy
        return session

    def test_optional_absent_attribute_is_allowed(self):
        for code in (ATTRIBUTE_UNSUPPORTED, NO_VALUE):
            with self.subTest(code=code):
                session = self.session_with_result(code)
                self.assertIsNone(session.attribute(10, "AXTitle", optional=True))
                session.release.assert_called_once_with(1)

    def test_required_absent_attribute_is_an_error(self):
        for code in (ATTRIBUTE_UNSUPPORTED, NO_VALUE):
            with self.subTest(code=code):
                session = self.session_with_result(code)
                with self.assertRaises(AXReadError):
                    session.attribute(10, "AXRole")

    def test_transport_and_invalid_element_errors_are_never_empty_values(self):
        for code in (CANNOT_COMPLETE, -25202, -25211):
            for optional in (False, True):
                with self.subTest(code=code, optional=optional):
                    session = self.session_with_result(code)
                    with self.assertRaises(AXReadError) as error:
                        session.attribute(10, "AXChildren", optional=optional)
                    self.assertEqual(error.exception.code, code)
                    self.assertEqual(error.exception.attribute, "AXChildren")

    def test_success_retains_the_value_for_the_snapshot(self):
        session = self.session_with_result(0, 99)
        self.assertEqual(session.attribute(10, "AXRole"), 99)
        self.assertEqual(session.owned, [99])

    def test_success_without_a_value_is_not_treated_as_absence(self):
        session = self.session_with_result(0)
        with self.assertRaisesRegex(RuntimeError, "success without a value"):
            session.attribute(10, "AXTitle", optional=True)
