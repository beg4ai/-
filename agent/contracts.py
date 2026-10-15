import json
import math
import re
from datetime import date, datetime
from urllib.parse import urlsplit
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
FORMATS = FormatChecker()


@FORMATS.checks("date-time", raises=(ValueError, TypeError))
def check_timestamp(value):
    if not isinstance(value, str):
        return True
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})", value):
        return False
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return "T" in value and parsed.tzinfo is not None


@FORMATS.checks("date", raises=(ValueError, TypeError))
def check_date(value):
    return not isinstance(value, str) or (len(value) == 10 and date.fromisoformat(value) is not None)


@FORMATS.checks("uri", raises=(ValueError, TypeError))
def check_uri(value):
    return not isinstance(value, str) or (bool(urlsplit(value).scheme) and not any(c.isspace() for c in value))


class ContractError(ValueError):
    pass


def schema(name):
    return json.loads((ROOT / "schemas" / f"{name}.json").read_text(encoding="utf-8"))


def validate(name, value, section=None):
    document = schema(name)
    if section:
        document = {**document, "$ref": f"#/$defs/{section}"}
    # JSON has no NaN/Infinity. Python's json decoder otherwise accepts them.
    def finite(item):
        if isinstance(item, float) and not math.isfinite(item):
            raise ContractError("non_finite_number")
        if isinstance(item, dict):
            for child in item.values():
                finite(child)
        elif isinstance(item, list):
            for child in item:
                finite(child)
    finite(value)
    errors = sorted(Draft202012Validator(document, format_checker=FORMATS).iter_errors(value),
                    key=lambda error: str(error.path))
    if errors:
        # Never echo arbitrary model arguments or secrets in error messages.
        error = errors[0]
        raise ContractError(f"{name}: {'/'.join(map(str, error.path)) or '$'}: {error.validator}")


TOOL_NAMES = ("weather.forecast", "maps.search", "maps.navigate", "health.summary",
              "calendar.events", "reminders.create")
