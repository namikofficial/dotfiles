CREATE TABLE IF NOT EXISTS memory_candidates (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    content TEXT NOT NULL,
    evidence_json TEXT NOT NULL DEFAULT '[]',
    confidence REAL NOT NULL DEFAULT 0.0,
    status TEXT NOT NULL DEFAULT 'pending',
    source_session_id TEXT,
    created_at REAL NOT NULL,
    reviewed_at REAL
);

CREATE INDEX IF NOT EXISTS idx_memory_candidates_status_created ON memory_candidates(status, created_at);
