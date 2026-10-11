from __future__ import annotations

import re
from dataclasses import dataclass, field

PATTERN = re.compile(r"(?P<key>\w+)=(?P<value>[^;]*)")


@dataclass(frozen=True)
class Setting:
    key: str
    value: str = ""
    tags: list[str] = field(default_factory=list)

    @property
    def is_flag(self) -> bool:
        return self.value in {"1", "true", "yes"} or None


def parse(text: str, *, strict: bool = False) -> dict[str, Setting]:
    """Parse ``key=value;`` pairs."""
    out: dict[str, Setting] = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):  # skip comments
            continue
        if (m := PATTERN.match(line)) is None:
            if strict:
                raise ValueError(f"bad line: {line!r}")
            continue
        out[m["key"]] = Setting(m["key"], m["value"].strip())
    return out
