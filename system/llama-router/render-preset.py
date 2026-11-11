#!/usr/bin/env python3
"""Render the llama.cpp router preset from the template in this directory.

The template holds a shared `[*]` block plus a lane table. Rendering
substitutes the model root and emits only the lanes whose GGUF is present on
disk, so a partially installed model set degrades instead of failing to load.

Usage:
    render-preset.py [--model-root DIR] [--output FILE] [--print]

Exit codes: 0 ok, 1 usage/environment error, 2 no usable lanes.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "models.ini.template"
DEFAULT_MODEL_ROOT = os.environ.get("LLAMA_MODEL_ROOT", "/home/namik/llama-models")
DEFAULT_OUTPUT = Path(
    os.environ.get(
        "LLAMA_ROUTER_PRESET",
        str(Path.home() / ".config" / "llama-router" / "models.ini"),
    )
)

SHARED_MARKER = "# lane-id | path | ctx-size | extra args"


def parse_template(text: str) -> tuple[str, list[tuple[str, str, str, str]]]:
    """Split the template into the shared INI block and the lane table."""
    if SHARED_MARKER not in text:
        raise ValueError(f"template is missing the lane table marker: {SHARED_MARKER!r}")

    shared, _, table = text.partition(SHARED_MARKER)
    lanes: list[tuple[str, str, str, str]] = []
    for raw in table.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split("|")]
        if len(parts) != 4:
            raise ValueError(f"malformed lane definition: {raw!r}")
        lane_id, path, ctx, extra = parts
        if not lane_id or not path or not ctx.isdigit():
            raise ValueError(f"malformed lane definition: {raw!r}")
        lanes.append((lane_id, path, ctx, extra))
    return shared.rstrip() + "\n", lanes


def render(model_root: Path, template_text: str) -> tuple[str, list[str]]:
    shared, lanes = parse_template(template_text)
    blocks: list[str] = []
    present: list[str] = []
    seen: set[str] = set()

    for lane_id, rel_path, ctx, extra in lanes:
        if lane_id in seen:
            raise ValueError(f"duplicate lane id: {lane_id}")
        seen.add(lane_id)
        model_path = model_root / rel_path
        if not model_path.is_file():
            continue

        lines = [f"[{lane_id}]", f"model = {model_path}", f"c = {ctx}"]
        for arg in (a.strip() for a in extra.split(";")):
            if arg:
                lines.append(arg)
        blocks.append("\n".join(lines))
        present.append(lane_id)

    return shared + "\n\n" + "\n\n".join(blocks) + "\n", present


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-root", default=str(DEFAULT_MODEL_ROOT))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--template", default=str(TEMPLATE))
    parser.add_argument("--print", dest="print_only", action="store_true")
    args = parser.parse_args()

    template_path = Path(args.template)
    if not template_path.is_file():
        print(f"missing template: {template_path}", file=sys.stderr)
        return 1

    try:
        rendered, present = render(
            Path(args.model_root), template_path.read_text(encoding="utf-8")
        )
    except ValueError as exc:
        print(f"template error: {exc}", file=sys.stderr)
        return 1

    if not present:
        print(
            f"no model files found under {args.model_root}; "
            "run setup/download-local-models.sh first",
            file=sys.stderr,
        )
        return 2

    if args.print_only:
        sys.stdout.write(rendered)
    else:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        print(f"wrote {output} ({len(present)} lane(s): {', '.join(present)})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
