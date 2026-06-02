CREATE TABLE IF NOT EXISTS task_runs (
    run_id TEXT PRIMARY KEY,
    repo TEXT,
    task TEXT NOT NULL,
    task_fingerprint TEXT NOT NULL,
    mode TEXT NOT NULL DEFAULT 'auto',
    max_subtasks INTEGER NOT NULL DEFAULT 8,
    graph_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    current_subtask_id TEXT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    finished_at REAL
);

CREATE INDEX IF NOT EXISTS idx_task_runs_repo_created ON task_runs(repo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_task_runs_repo_status ON task_runs(repo, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS task_outcomes (
    outcome_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    repo TEXT,
    task_id TEXT NOT NULL,
    task TEXT NOT NULL,
    task_fingerprint TEXT NOT NULL,
    subtask_id TEXT NOT NULL,
    subtask_title TEXT NOT NULL,
    subtask_type TEXT NOT NULL,
    status TEXT NOT NULL,
    retrieved_files_json TEXT NOT NULL DEFAULT '[]',
    edited_files_json TEXT NOT NULL DEFAULT '[]',
    missed_files_json TEXT NOT NULL DEFAULT '[]',
    useless_files_json TEXT NOT NULL DEFAULT '[]',
    checks_run_json TEXT NOT NULL DEFAULT '[]',
    passed INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    attempt INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_task_outcomes_repo_created ON task_outcomes(repo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_task_outcomes_run_created ON task_outcomes(run_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_task_outcomes_task_hash ON task_outcomes(repo, task_fingerprint, created_at DESC);

CREATE TABLE IF NOT EXISTS task_lessons (
    lesson_id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT,
    run_id TEXT,
    task_id TEXT NOT NULL,
    lesson_kind TEXT NOT NULL,
    lesson_json TEXT NOT NULL DEFAULT '{}',
    created_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_task_lessons_repo_created ON task_lessons(repo, created_at DESC);
