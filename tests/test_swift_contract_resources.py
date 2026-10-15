import json
import re
import unittest

from agent.contracts import ROOT
from scripts.sync_swift_contracts import PACKAGE, resources


class SwiftResourceTests(unittest.TestCase):
    """Resource and vocabulary checks only; these do not validate Swift compilation."""

    def test_swift_resources_match_canonical_contracts(self):
        for source, target in resources():
            with self.subTest(file=source.name):
                self.assertEqual(source.read_bytes(), target.read_bytes())

    def test_schema_vocabulary_has_no_silent_swift_gaps(self):
        source = (PACKAGE / "Sources/DongShaoCore/SchemaValidator.swift").read_text(encoding="utf-8")
        declared = re.search(r"let supported: Set<String> = \[(.*?)\]", source, re.S)
        self.assertIsNotNone(declared)
        supported = set(re.findall(r'"([^"\n]+)"', declared[1]))

        def check(schema):
            self.assertTrue(set(schema).issubset(supported), set(schema) - supported)
            for key in ("properties", "$defs"):
                for child in schema.get(key, {}).values():
                    check(child)
            if "items" in schema:
                check(schema["items"])

        for path in (ROOT / "schemas").glob("*.json"):
            with self.subTest(schema=path.name):
                check(json.loads(path.read_text(encoding="utf-8")))
