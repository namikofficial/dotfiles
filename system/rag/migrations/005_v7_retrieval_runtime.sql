CREATE TABLE IF NOT EXISTS retrieval_runs (
    id TEXT PRIMARY KEY,
    repo TEXT,
    branch TEXT,
    mode TEXT NOT NULL,
    intent TEXT,
    query TEXT NOT NULL,
    plan_json TEXT NOT NULL DEFAULT '{}',
    rewrites_json TEXT NOT NULL DEFAULT '[]',
    candidate_counts_json TEXT NOT NULL DEFAULT '{}',
    selected_files_json TEXT NOT NULL DEFAULT '[]',
    edit_scope_json TEXT NOT NULL DEFAULT '{}',
    missing_context_json TEXT NOT NULL DEFAULT '{}',
    packed_context_token_estimate INTEGER NOT NULL DEFAULT 0,
    timings_json TEXT NOT NULL DEFAULT '{}',
    warnings_json TEXT NOT NULL DEFAULT '[]',
    errors_json TEXT NOT NULL DEFAULT '[]',
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_retrieval_runs_repo_created ON retrieval_runs(repo, created_at DESC);

CREATE TABLE IF NOT EXISTS retrieval_outcomes (
    outcome_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT,
    repo TEXT,
    task TEXT NOT NULL,
    task_fingerprint TEXT NOT NULL,
    retrieved_files_json TEXT NOT NULL DEFAULT '[]',
    edited_files_json TEXT NOT NULL DEFAULT '[]',
    checks_run_json TEXT NOT NULL DEFAULT '[]',
    passed INTEGER NOT NULL DEFAULT 0,
    notes TEXT,
    missed_files_json TEXT NOT NULL DEFAULT '[]',
    created_at REAL NOT NULL,
    FOREIGN KEY(run_id) REFERENCES retrieval_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_retrieval_outcomes_repo_created ON retrieval_outcomes(repo, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_retrieval_outcomes_task_hash ON retrieval_outcomes(repo, task_fingerprint, created_at DESC);

CREATE TABLE IF NOT EXISTS retrieval_cache (
    repo TEXT NOT NULL,
    path TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'hot',
    score REAL NOT NULL DEFAULT 0.0,
    hits INTEGER NOT NULL DEFAULT 0,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    updated_at REAL NOT NULL,
    PRIMARY KEY(repo, path, kind)
);

CREATE INDEX IF NOT EXISTS idx_retrieval_cache_repo_updated ON retrieval_cache(repo, updated_at DESC);

CREATE TABLE IF NOT EXISTS eval_runs (
    id TEXT PRIMARY KEY,
    repo TEXT,
    case_count INTEGER NOT NULL DEFAULT 0,
    metrics_json TEXT NOT NULL DEFAULT '{}',
    created_at REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_eval_runs_repo_created ON eval_runs(repo, created_at DESC);
