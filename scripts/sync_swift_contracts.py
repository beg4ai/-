"""Copy canonical contracts for SwiftPM resources; --check detects migration drift.

This checks resource parity only. It does not compile or test Swift source.
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "iOS/Packages/DongShaoCore"


def resources():
    for source in sorted((ROOT / "schemas").glob("*.json")):
        yield source, PACKAGE / "Sources/DongShaoCore/Resources/schemas" / source.name
    yield ROOT / "fixtures/tool-cases.json", PACKAGE / "Tests/DongShaoCoreTests/Resources/tool-cases.json"
    yield ROOT / "contracts/tool-manifest.json", PACKAGE / "Sources/DongShaoCore/Resources/tool-manifest.json"
    yield ROOT / "config/automations.json", PACKAGE / "Sources/DongShaoCore/Resources/automation-rules.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    drift = []
    for source, destination in resources():
        data = source.read_bytes()
        if args.check:
            if not destination.exists() or destination.read_bytes() != data:
                drift.append(str(destination.relative_to(ROOT)))
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
    if drift:
        print("Swift resource drift:\n" + "\n".join(drift))
        return 1
    print("Swift JSON resources match canonical files; Swift compilation not checked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
