import json
from pathlib import Path

from .contracts import ROOT, ContractError, validate


def load_rules(path=None):
    rules = json.loads((Path(path) if path else ROOT / "config/automations.json").read_text(encoding="utf-8"))
    validate("automation-policy", rules)
    if rules["running_min_c"] >= rules["running_max_c"]:
        raise ContractError("running_min_c must be less than running_max_c")
    return rules
