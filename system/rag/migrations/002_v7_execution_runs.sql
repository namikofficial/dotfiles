CREATE TABLE IF NOT EXISTS execution_runs (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    repo TEXT,
    target TEXT NOT NULL,
    profile_id TEXT,
    intent TEXT,
    mode TEXT,
    risk_level TEXT,
    query TEXT NOT NULL,
    prompt_hash TEXT,
    agent_plan_json TEXT NOT NULL,
    status TEXT NOT NULL,
    stdout TEXT,
    stderr TEXT,
    exit_code INTEGER,
    duration_ms INTEGER,
    files_modified TEXT NOT NULL DEFAULT '[]',
    started_at REAL,
    finished_at REAL
);

CREATE INDEX IF NOT EXISTS idx_execution_runs_repo_started ON execution_runs(repo, started_at);
CREATE INDEX IF NOT EXISTS idx_execution_runs_session ON execution_runs(session_id);
