import unittest

from project_capabilities import normalize, SERIALIZED


class CapabilityMetadataTests(unittest.TestCase):
    def test_stringified_metadata_preserves_existing_dictionary_and_other_settings(self):
        original = 'before\n\t\t' + SERIALIZED + '\nCODE_SIGN_STYLE = Automatic;\nafter\n'
        expected = ('before\n\t\tSystemCapabilities = {\n'
                    '\t\t\tcom.apple.AssociatedDomains = {\n'
                    '\t\t\t\tenabled = 1;\n\t\t\t};\n\t\t};\n'
                    'CODE_SIGN_STYLE = Automatic;\nafter\n')
        self.assertEqual(normalize(original), expected)
        self.assertEqual(normalize(expected), expected)

    def test_unknown_missing_or_duplicate_capabilities_fail_closed(self):
        for text in ['', SERIALIZED + '\n' + SERIALIZED,
                     SERIALIZED.replace('enabled\\\": 1', 'enabled\\\": 0'),
                     SERIALIZED.replace('AssociatedDomains', 'OtherCapability')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                normalize(text)


if __name__ == "__main__":
    unittest.main()
