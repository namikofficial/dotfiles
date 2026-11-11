#!/usr/bin/env python3
"""Agentic-coding eval for the local llama.cpp router lanes.

Scores what actually matters for a coding agent, not prose quality:

  basic  think-block integrity, tool-call format and correctness, and a
         read -> write round trip that must produce a correct file.
  hard   read -> find a bug -> edit -> run the test suite -> converge.
         Includes a repeated-identical-call check for tool-call loops.

Usage:
    setup/eval-local-models.py [--scenario basic|hard|both] [--base URL]
                               [--json] MODEL [MODEL ...]

Exit codes: 0 all models passed, 1 at least one model failed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path

WORKSPACE = Path("/tmp/llama-router-eval")
NOTES = "notes.txt"
OUTPUT = "summary.txt"
EXPECTED_LINE = "Task: wire the llama router into pi CLI"

BUGGY = '''\
def running_total(values):
    total = 0
    for i, v in enumerate(values):
        if i < len(values) - 1:
            total += v
    return total


def average(values):
    return running_total(values) / len(values)
'''

TEST = '''\
from calc import running_total, average

assert running_total([1, 2, 3]) == 6, running_total([1, 2, 3])
assert running_total([5]) == 5, running_total([5])
assert average([2, 4, 6]) == 4.0, average([2, 4, 6])
print("ALL TESTS PASSED")
'''

READ_TOOL = {
    "type": "function",
    "function": {
        "name": "read",
        "description": "Read a file from disk",
        "parameters": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
        },
    },
}

WRITE_TOOL = {
    "type": "function",
    "function": {
        "name": "write",
        "description": "Write content to a file",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "content": {"type": "string"},
            },
            "required": ["path", "content"],
        },
    },
}

EDIT_TOOL = {
    "type": "function",
    "function": {
        "name": "edit",
        "description": "Replace an exact string in a file",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "old_string": {"type": "string"},
                "new_string": {"type": "string"},
            },
            "required": ["path", "old_string", "new_string"],
        },
    },
}

BASH_TOOL = {
    "type": "function",
    "function": {
        "name": "bash",
        "description": "Run a shell command",
        "parameters": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"],
        },
    },
}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


def post(base: str, path: str, payload: dict, timeout: int = 300) -> dict:
    request = urllib.request.Request(
        base.rstrip("/") + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode())


def check_think_block(text: str) -> tuple[bool, str]:
    """An orphan </think> or an unclosed <think> means the model is confused.

    This is the failure mode that makes a quant unusable for agent work even
    when its raw text quality looks fine.
    """
    opens = text.count("<think>")
    closes = text.count("</think>")
    if closes > opens:
        return False, f"orphan </think> (opens={opens} closes={closes})"
    if opens > closes:
        return False, f"unclosed <think> (opens={opens} closes={closes})"
    return True, "ok"


def detect_loop(call_keys: list[str]) -> tuple[bool, str]:
    """A real agent loop repeats the IDENTICAL call.

    Calling the same tool with different arguments - for example re-running
    the test suite after each edit - is normal behaviour, not a loop.
    """
    if not call_keys:
        return False, ""
    counts = Counter(call_keys)
    (key, count) = counts.most_common(1)[0]
    if count >= 3:
        return True, f"identical call repeated {count}x: {key[:80]}"
    tail = call_keys[-6:]
    if len(tail) == 6 and len(set(tail)) <= 2:
        return True, f"cyclic tool pattern: {tail}"
    return False, ""


def reset_workspace() -> Path:
    shutil.rmtree(WORKSPACE, ignore_errors=True)
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    (WORKSPACE / NOTES).write_text(
        "Project: NoxFlow\nOwner: namik\n"
        f"{EXPECTED_LINE}\nStatus: in progress\n",
        encoding="utf-8",
    )
    (WORKSPACE / "calc.py").write_text(BUGGY, encoding="utf-8")
    (WORKSPACE / "test_calc.py").write_text(TEST, encoding="utf-8")
    return WORKSPACE


def run_tool(name: str, args: dict, workspace: Path) -> str:
    if name == "read":
        try:
            return Path(args.get("path", "")).read_text(encoding="utf-8")
        except OSError as exc:
            return f"error: {exc}"
    if name == "write":
        try:
            Path(args.get("path", "")).write_text(
                args.get("content", ""), encoding="utf-8"
            )
            return "written"
        except OSError as exc:
            return f"error: {exc}"
    if name == "edit":
        try:
            path = Path(args.get("path", ""))
            body = path.read_text(encoding="utf-8")
            old = args.get("old_string", "")
            new = args.get("new_string", "")
            if old and old in body:
                path.write_text(body.replace(old, new, 1), encoding="utf-8")
                return "edit applied"
            return "error: old_string not found in file"
        except OSError as exc:
            return f"error: {exc}"
    if name == "bash":
        try:
            proc = subprocess.run(
                args.get("command", ""),
                shell=True,
                cwd=workspace,
                capture_output=True,
                text=True,
                timeout=30,
            )
            return (proc.stdout + proc.stderr)[-800:]
        except subprocess.TimeoutExpired:
            return "error: command timed out"
    return f"error: unknown tool {name}"


def agent_loop(
    base: str,
    model: str,
    messages: list[dict],
    tools: list[dict],
    workspace: Path,
    max_turns: int,
    max_tokens: int,
) -> dict:
    """Drive a real tool-using loop and return what the model did."""
    call_keys: list[str] = []
    used: set[str] = set()
    transcript: list[str] = []
    finish = ""
    usage: dict = {}
    turns = 0

    for _ in range(max_turns):
        turns += 1
        response = post(
            base,
            "/chat/completions",
            {
                "model": model,
                "messages": messages,
                "tools": tools,
                "max_tokens": max_tokens,
                "temperature": 0.1,
            },
        )
        usage = response.get("usage", {})
        message = response["choices"][0]["message"]
        finish = str(response["choices"][0].get("finish_reason"))
        transcript.append(json.dumps(message))
        calls = message.get("tool_calls") or []
        if not calls:
            break

        messages.append(
            {
                "role": "assistant",
                "content": message.get("content") or "",
                "tool_calls": calls,
            }
        )
        for call in calls:
            function = call.get("function", {})
            name = function.get("name")
            try:
                args = json.loads(function.get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            used.add(str(name))
            call_keys.append(f"{name}|{json.dumps(args, sort_keys=True)}")
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call.get("id", "x"),
                    "content": run_tool(str(name), args, workspace),
                }
            )

    return {
        "turns": turns,
        "finish": finish,
        "usage": usage,
        "used": used,
        "call_keys": call_keys,
        "transcript": "\n".join(transcript),
    }


# --------------------------------------------------------------------------
# scenarios
# --------------------------------------------------------------------------


def scenario_basic(base: str, model: str) -> dict:
    workspace = reset_workspace()
    notes = workspace / NOTES
    out = workspace / OUTPUT
    out.unlink(missing_ok=True)

    first = post(
        base,
        "/chat/completions",
        {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "You are a coding assistant. Use tools when appropriate.",
                },
                {
                    "role": "user",
                    "content": (
                        f"Read the file {notes} and tell me what it contains."
                    ),
                },
            ],
            "tools": [READ_TOOL],
            "max_tokens": 600,
            "temperature": 0.1,
        },
    )
    message = first["choices"][0]["message"]
    calls = message.get("tool_calls") or []
    think_ok, think_detail = check_think_block(json.dumps(message))

    correct = False
    if calls:
        function = calls[0].get("function", {})
        try:
            args = json.loads(function.get("arguments") or "{}")
        except json.JSONDecodeError:
            args = {}
        correct = function.get("name") == "read" and NOTES in str(args.get("path", ""))

    looped, loop_detail = detect_loop(
        [
            f"{c.get('function', {}).get('name')}|"
            f"{c.get('function', {}).get('arguments', '')}"
            for c in calls
        ]
    )

    second = agent_loop(
        base,
        model,
        [
            {
                "role": "system",
                "content": "You are a coding assistant with file tools.",
            },
            {
                "role": "user",
                "content": (
                    f"Read {notes}, extract the line that starts with 'Task:', "
                    f"and write that exact line to {out} using the write tool. "
                    "Do not add commentary."
                ),
            },
        ],
        [READ_TOOL, WRITE_TOOL],
        workspace,
        max_turns=6,
        max_tokens=900,
    )
    wrote = "write" in second["used"]
    written = out.read_text(encoding="utf-8").strip() if out.exists() else ""

    checks = {
        "think_block": (think_ok, think_detail),
        "tool_call_present": (bool(calls), f"{len(calls)} tool_call(s)"),
        "tool_call_correct": (correct, json.dumps(calls)[:120]),
        "terminated": (
            first["choices"][0].get("finish_reason") != "length",
            str(first["choices"][0].get("finish_reason")),
        ),
        "write_called": (wrote, f"write tool executed={wrote}"),
        "file_correct": (
            written == EXPECTED_LINE,
            f"got {written!r}",
        ),
        "no_loop": (not looped, loop_detail or "ok"),
        "terminated_in_loop": (
            second["finish"] != "length",
            f"finish={second['finish']} turns={second['turns']}",
        ),
    }
    return {
        "checks": checks,
        "turns": second["turns"],
        "usage": second["usage"],
    }


def scenario_hard(base: str, model: str) -> dict:
    workspace = reset_workspace()

    loop = agent_loop(
        base,
        model,
        [
            {
                "role": "system",
                "content": "You are a senior engineer debugging a failing test suite.",
            },
            {
                "role": "user",
                "content": (
                    "The test suite in this directory is failing. Read calc.py, find the "
                    "bug, fix it, then run `python3 test_calc.py` with bash until the "
                    "tests pass. Do not modify test_calc.py."
                ),
            },
        ],
        [READ_TOOL, EDIT_TOOL, BASH_TOOL],
        workspace,
        max_turns=14,
        max_tokens=1200,
    )

    try:
        proc = subprocess.run(
            ["python3", "test_calc.py"],
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=30,
        )
        passed = proc.returncode == 0
        test_output = (proc.stdout + proc.stderr).strip()[-90:]
    except subprocess.TimeoutExpired:
        passed = False
        test_output = "test timeout"

    source = (workspace / "calc.py").read_text(encoding="utf-8")
    correct_patch = "total += v" in source and "i < len(values) - 1" not in source
    looped, loop_detail = detect_loop(loop["call_keys"])
    think_ok, think_detail = check_think_block(loop["transcript"])

    checks = {
        "used_read": ("read" in loop["used"], "read called"),
        "used_edit": ("edit" in loop["used"], "edit called"),
        "used_bash": ("bash" in loop["used"], "bash called"),
        "tests_pass": (passed, test_output or "tests passed"),
        "correct_patch": (
            correct_patch,
            "intended fix applied" if correct_patch else "wrong or partial patch",
        ),
        "think_block": (think_ok, think_detail),
        "no_loop": (not looped, loop_detail or "ok"),
        "bounded_turns": (loop["turns"] <= 14, f"{loop['turns']} turns (max 14)"),
        "terminated": (loop["finish"] != "length", f"finish={loop['finish']}"),
    }
    return {
        "checks": checks,
        "turns": loop["turns"],
        "usage": loop["usage"],
    }


# --------------------------------------------------------------------------
# driver
# --------------------------------------------------------------------------


def run_model(base: str, model: str, scenario: str) -> dict:
    started = time.time()
    try:
        if scenario == "basic":
            result = scenario_basic(base, model)
        else:
            result = scenario_hard(base, model)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        return {"model": model, "scenario": scenario, "error": f"request failed: {exc}"}

    checks = result["checks"]
    passed = sum(1 for ok, _ in checks.values() if ok)
    return {
        "model": model,
        "scenario": scenario,
        "checks": {k: {"ok": ok, "detail": detail} for k, (ok, detail) in checks.items()},
        "passed": passed,
        "total": len(checks),
        "turns": result["turns"],
        "seconds": round(time.time() - started, 1),
        "usage": result["usage"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="+")
    parser.add_argument("--base", default="http://127.0.0.1:8080/v1")
    parser.add_argument("--scenario", choices=("basic", "hard", "both"), default="both")
    parser.add_argument("--json", dest="as_json", action="store_true")
    args = parser.parse_args()

    scenarios = ["basic", "hard"] if args.scenario == "both" else [args.scenario]
    failures = 0
    results = []

    for model in args.models:
        for scenario in scenarios:
            result = run_model(args.base, model, scenario)
            results.append(result)
            if "error" in result:
                failures += 1
                if not args.as_json:
                    print(f"\n=== {model} [{scenario}] — ERROR {result['error']}")
                continue
            if not args.as_json:
                print(
                    f"\n=== {model} [{scenario}] — "
                    f"{result['passed']}/{result['total']} checks passed "
                    f"({result['seconds']}s, {result['turns']} turns)"
                )
                for name, detail in result["checks"].items():
                    print(f"  {'PASS' if detail['ok'] else 'FAIL'}  {name:<22} {detail['detail'][:100]}")
                usage = result.get("usage") or {}
                if usage:
                    print(
                        f"  usage: prompt={usage.get('prompt_tokens')} "
                        f"completion={usage.get('completion_tokens')}"
                    )
            if result.get("passed", 0) < result.get("total", 0):
                failures += 1

    if args.as_json:
        print(json.dumps(results, indent=2))

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
