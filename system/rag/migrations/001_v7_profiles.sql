CREATE TABLE IF NOT EXISTS profiles (
    id TEXT PRIMARY KEY,
    yaml_source TEXT NOT NULL,
    is_user_override INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS profile_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    profile_id TEXT NOT NULL,
    session_id TEXT,
    selected INTEGER NOT NULL DEFAULT 1,
    confidence REAL NOT NULL DEFAULT 0.0,
    used_at REAL NOT NULL,
    FOREIGN KEY(profile_id) REFERENCES profiles(id)
);
