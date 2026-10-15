import json
import re
import unittest

from agent.contracts import ROOT, TOOL_NAMES, validate


class StandaloneArchitectureTests(unittest.TestCase):
    def test_manifest_meets_appendix_a(self):
        manifest = json.loads((ROOT / "contracts/tool-manifest.json").read_text(encoding="utf-8"))
        validate("tool-manifest", manifest)
        self.assertEqual({item["name"] for item in manifest["tools"]}, set(TOOL_NAMES))
        self.assertEqual(len(manifest["tools"]), len(TOOL_NAMES))
        for item in manifest["tools"]:
            for direction in ("input", "output"):
                self.assertEqual(item[f"{direction}_schema"], f"urn:dongshao:v1:{item['name']}#/$defs/{direction}")
            if item["risk"] != "readOnly":
                self.assertTrue(item["requires_confirmation"])

    def test_swift_core_libraries_do_not_import_ios_frameworks_or_test_drivers(self):
        packages = ROOT / "iOS/Packages"
        forbidden_imports = r"(?m)^\s*import\s+(UIKit|HealthKit|AppIntents|EventKit|CoreLocation|MapKit|XCTest)\b"
        for package in ("DongShaoCore", "DongShaoProviders", "DongShaoWorkflows"):
            for path in (packages / package / "Sources" / package).glob("*.swift"):
                text = path.read_text(encoding="utf-8")
                self.assertIsNone(re.search(forbidden_imports, text), str(path))
                self.assertNotRegex(text.lower(), r"webdriveragent|appium|ios-tagent|pythonkit|python\.import")

    def test_production_workflow_library_does_not_link_mocks_or_providers(self):
        manifest = (ROOT / "iOS/Packages/DongShaoWorkflows/Package.swift").read_text(encoding="utf-8")
        target = re.search(r'\.target\(name: "DongShaoWorkflows", dependencies: \[([^\]]*)\]', manifest)
        self.assertIsNotNone(target)
        self.assertEqual(re.findall(r'"([^"]+)"', target[1]), ["DongShaoCore"])
