# Waylandar-style Calendar Backend

Syncs Google Calendar (via gcalcli) to a JSON cache file that NoxFlow's QML
CalendarModel reads via FileView.

## Setup

```bash
# One-time auth
pip install gcalcli google-auth-oauthlib
python sync.py --auth
# Follow the OAuth URL, paste the token.

# Background sync (every 5 min)
python sync.py --background
# Or manually:
python sync.py --cache ~/.local/state/noxflow/calendar.json
```

## OAuth Security

The `--auth` step creates:
- `config.json` — account settings
- `credentials.json` — Google OAuth client ID/secret (do NOT commit)
- `token_*.json` — per-account OAuth tokens (do NOT commit)

All these are in `.gitignore`. Never commit them.

## Sync Script API

```
usage: sync.py [-h] [--auth] [--cache PATH] [--background]
               [--interval MINUTES]

Fetch calendar events to a JSON cache file.

optional arguments:
  --auth              Run OAuth setup wizard
  --cache PATH        Write cache to PATH (default: ./cache.json)
  --background        Background mode with periodic sync
  --interval MINUTES  Sync interval in minutes (default: 5)
```

## Cache JSON format

```json
{
  "events": [
    {
      "date": "2026-07-28",
      "title": "Team standup",
      "time": "10:00",
      "duration": "30m",
      "calendar": "Work",
      "calendarColor": "#4285f4",
      "description": "Daily sync",
      "location": "Meeting Room 3",
      "allDay": false
    }
  ],
  "lastSync": "2026-07-28T12:00:00Z",
  "calendars": ["Work", "Personal", "Holidays"],
  "errors": []
}
```
