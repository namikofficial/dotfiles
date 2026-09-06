#!/usr/bin/env python3
"""
Waylandar-style calendar sync backend.
Fetches Google Calendar events via gcalcli, writes JSON cache for QML FileView.
"""

import argparse
import calendar
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone

CONFIG_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CACHE = os.path.join(CONFIG_DIR, "cache.json")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
GCALCLI_CONFIG = CONFIG_DIR  # absolute path


def log(msg):
    print(f"[calendar-sync] {msg}", flush=True)


# ── Utility ─────────────────────────────────────────────────────────────────

def days_in_month(year, month):
    """Return the number of days in the given month (0-indexed month)."""
    return calendar.monthrange(year, month + 1)[1]


def clamp_selected_day(day, year, month):
    """Clamp day to the valid range for the given month."""
    return max(1, min(day, days_in_month(year, month)))


def event_id(date_str, title, time_str, calendar_name):
    """Stable hash id for deduplication — different events get different ids."""
    raw = f"{date_str}|{title}|{time_str or ''}|{calendar_name or ''}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            return json.load(f)
    return {}


def save_config(config):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2)


def gcalcli(args):
    """Run gcalcli with config pointing to our directory."""
    cmd = ["gcalcli", "--config-folder", GCALCLI_CONFIG] + args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return result
    except subprocess.TimeoutExpired:
        return None
    except FileNotFoundError:
        return None


def run_auth():
    """Interactive OAuth setup via gcalcli."""
    log("Starting gcalcli OAuth setup...")
    result = gcalcli(["list"])
    if result is None:
        log("ERROR: gcalcli not found. Install: pip install gcalcli")
        return False
    if result.returncode == 0:
        log("Auth successful! Calendars found.")
        return True
    else:
        log("Failed. Follow the URL above, paste the token, then re-run.")
        return False


def parse_gcalcli_tsv(output):
    """Parse gcalcli --tsv agenda output into event dicts.
    TSV columns: start_date, start_time, end_date, end_time, title
    All-day events have empty start_time/end_time.
    """
    events = []
    if not output or not output.strip():
        return events

    lines = output.strip().split("\n")
    if len(lines) < 2:
        return events

    # First line is header
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue

        start_date = parts[0].strip()
        start_time = parts[1].strip()
        end_date = parts[2].strip()
        end_time = parts[3].strip()
        title = parts[4].strip()

        if not title:
            continue

        # Calculate duration
        duration = ""
        if start_time and end_time and start_date and end_date:
            try:
                start_dt = datetime.fromisoformat(f"{start_date}T{start_time}")
                end_dt = datetime.fromisoformat(f"{end_date}T{end_time}")
                diff_sec = (end_dt - start_dt).total_seconds()
                if diff_sec > 0:
                    duration = f"{int(diff_sec // 60)}m"
            except ValueError:
                pass

        cal_name = "primary"
        events.append({
            "id": event_id(start_date, title, start_time, cal_name),
            "date": start_date,
            "title": title,
            "time": start_time,
            "duration": duration,
            "calendar": cal_name,
            "calendarColor": "#4285f4",
            "description": "",
            "location": "",
            "allDay": not bool(start_time),
        })

    return events


def parse_gcalcli_json(lines):
    """Parse gcalcli output when format is not JSON — handle line mode."""
    events = []
    current = {}
    for line in lines.split("\n"):
        line = line.strip()
        if not line:
            if current and current.get("summary"):
                events.append(current)
                current = {}
            continue
        if line.startswith("title:") or line.startswith("Title:"):
            if current and current.get("summary"):
                events.append(current)
            current = {"summary": line.split(":", 1)[1].strip()}
        elif ":" in line:
            key, val = line.split(":", 1)
            key = key.strip().lower()
            val = val.strip()
            if key == "start date":
                current["start_date"] = val
            elif key == "start time":
                current["start_time"] = val
            elif key == "end date":
                current["end_date"] = val
            elif key == "end time":
                current["end_time"] = val
            elif key == "description":
                current["description"] = val
            elif key == "location":
                current["location"] = val
            elif key == "calendar":
                current["calendar"] = val

    if current and current.get("summary"):
        events.append(current)

    return events


def list_calendars():
    """Get available calendar names from gcalcli."""
    result = gcalcli(["--nocolor", "list"])
    if result is None or result.returncode != 0:
        return []
    cals = []
    for line in result.stdout.strip().split("\n"):
        # Skip header/separator lines
        if "Access" in line or "-----" in line or not line.strip():
            continue
        parts = line.strip().split(None, 1)
        if len(parts) == 2:
            cals.append(parts[1].strip())
    return cals


def fetch_events(config):
    """Fetch events from all available calendars."""
    events = []
    errors = []

    calendars = config.get("calendars", [])
    look_ahead = config.get("look_ahead_days", 30)
    # gcalcli end date is exclusive — add 1 day to include look_ahead range
    end_date = (datetime.now(timezone.utc) + timedelta(days=look_ahead + 1)).strftime("%Y-%m-%d")

    log(f"Fetching events, {look_ahead} days ahead...")

    # Get all events (gcalcli defaults to all calendars)
    try:
        result = gcalcli(["--nocolor", "agenda", "--tsv", "today", end_date])
    except Exception as ex:
        errors.append(f"Exception: {ex}")
        return events, [], errors

    if result is None:
        errors.append("gcalcli not found")
        return events, [], errors
    if result.returncode != 0:
        errors.append(f"gcalcli error: {result.stderr.strip()}")
        return events, [], errors

    cal_events = parse_gcalcli_tsv(result.stdout)
    events.extend(cal_events)

    log(f"  → {len(events)} raw events")

    # Deduplicate by stable event id (date + title + time + calendar hash)
    # Distinct events with the same title but different times/calendars get different ids.
    seen_ids = set()
    unique = []
    for e in sorted(events, key=lambda x: x.get("date", "") + x.get("time", "")):
        eid = e.get("id", event_id(e.get("date", ""), e.get("title", ""),
                                    e.get("time", ""), e.get("calendar", "")))
        if eid not in seen_ids:
            seen_ids.add(eid)
            unique.append(e)

    # Color mapping
    color_map = {
        "primary": "#4285f4",
        "Work": "#db4437",
        "Personal": "#0f9d58",
        "Family": "#ab47bc",
        "Holidays": "#e67c73",
        "Arsenal": "#f4b400",
        "Hindu Holidays": "#e67c73",
    }

    cal_list = []
    seen_cals = set()
    for e in unique:
        cal_name = e.get("calendar", "primary")
        if cal_name not in seen_cals:
            seen_cals.add(cal_name)
            cal_list.append({
                "name": cal_name,
                "color": color_map.get(cal_name, "#4285f4"),
                "visible": config.get("calendar_visible", {}).get(cal_name, True),
            })
        e["calendarColor"] = color_map.get(cal_name, "#4285f4")

    log(f"  → {len(unique)} events, {len(cal_list)} calendars")

    return unique, cal_list, errors


def write_cache_atomic(events, calendars, errors, path):
    """Atomically write events to JSON cache.

    Uses a temp file + os.rename for atomic POSIX semantics.
    If events is empty AND errors is empty, skips the write to preserve
    any previously-cached good data (transient failure with no partial result).
    """
    # A successful empty result can be a valid empty calendar, but a failed
    # fetch must never replace the last-good event list with an empty one.
    if errors and os.path.exists(path):
        log("  → sync failed; preserving existing calendar cache")
        return
    if not events and not errors and os.path.exists(path):
        log("  → cache unchanged (no events, no errors) — preserving existing cache")
        return

    cache = {
        "events": events,
        "calendars": calendars,
        "lastSync": datetime.now(timezone.utc).isoformat(),
        "errors": errors,
    }
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

    dir_path = os.path.dirname(path) or "."
    fd, tmp_path = tempfile.mkstemp(dir=dir_path, suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(cache, f)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp_path, path)
    except Exception:
        # Clean up temp file on failure
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


# Keep the original public name for scripts and older callers.
def write_cache(events, calendars, errors, path):
    return write_cache_atomic(events, calendars, errors, path)


def run_sync(path, config):
    """Single sync pass."""
    events, calendars, errors = fetch_events(config)
    write_cache_atomic(events, calendars, errors, path)
    if errors:
        log(f"Warnings: {' / '.join(errors)}")
    return len(errors) == 0


def run_background(path, interval_minutes):
    """Continuous background sync."""
    config = load_config()
    log(f"Background sync every {interval_minutes} minutes. Cache: {path}")
    while True:
        run_sync(path, config)
        log(f"Next sync in {interval_minutes} minutes...")
        time.sleep(interval_minutes * 60)


def main():
    parser = argparse.ArgumentParser(description="Fetch calendar events to JSON cache")
    parser.add_argument("--auth", action="store_true", help="Run OAuth setup wizard")
    parser.add_argument("--cache", default=DEFAULT_CACHE, help=f"Cache file path (default: {DEFAULT_CACHE})")
    parser.add_argument("--background", action="store_true", help="Background mode with periodic sync")
    parser.add_argument("--interval", type=int, default=5, help="Sync interval in minutes (default: 5)")
    parser.add_argument("--look-ahead", type=int, default=30, help="Days to look ahead (default: 30)")
    args = parser.parse_args()

    if args.auth:
        success = run_auth()
        sys.exit(0 if success else 1)

    config = load_config()
    config["look_ahead_days"] = args.look_ahead
    if not config.get("calendars"):
        config["calendars"] = ["primary"]

    if args.background:
        run_background(args.cache, args.interval)
    else:
        sys.exit(0 if run_sync(args.cache, config) else 1)


if __name__ == "__main__":
    main()
