//! The local, on-device data model as SQLite DDL.
//!
//! Wanderlust is local-first (ADR-0004): everything lives in one SQLite file on
//! the phone, always exportable, never synced by default. This is a future
//! area/notes schema sketch, not the currently applied database schema. The
//! implemented recording/coverage schema and migrations live in
//! app/lib/recording/walk_store.dart.

/// Current schema version. Bump when `SCHEMA_SQL` changes; migrations key off it.
pub const SCHEMA_VERSION: u32 = 1;

/// Full schema. Coordinates are stored as REAL lng/lat; segment geometry as an
/// encoded polyline string to keep rows compact. Timestamps are RFC3339 text.
pub const SCHEMA_SQL: &str = r#"
-- A downloaded area (home area or a travel "passport" area).
CREATE TABLE IF NOT EXISTS area (
    id            INTEGER PRIMARY KEY,
    name          TEXT    NOT NULL,
    kind          TEXT    NOT NULL,           -- 'admin' | 'drawn'
    bbox          TEXT    NOT NULL,           -- "minLng,minLat,maxLng,maxLat"
    pmtiles_path  TEXT,                       -- local path to the offline tiles
    created_at    TEXT    NOT NULL
);

-- A walkable street edge within an area. `osm_id` ties back to OpenStreetMap.
CREATE TABLE IF NOT EXISTS segment (
    id       INTEGER PRIMARY KEY,
    area_id  INTEGER NOT NULL REFERENCES area(id) ON DELETE CASCADE,
    osm_id   INTEGER,
    geom     TEXT    NOT NULL                 -- encoded polyline
);
CREATE INDEX IF NOT EXISTS idx_segment_area ON segment(area_id);

-- The reward: how often each segment has been walked. One row per walked edge.
CREATE TABLE IF NOT EXISTS walk_count (
    segment_id   INTEGER PRIMARY KEY REFERENCES segment(id) ON DELETE CASCADE,
    count        INTEGER NOT NULL DEFAULT 0,
    last_walked  TEXT
);

-- A recorded outing (live or imported), and its raw points (kept for export
-- and re-matching if the algorithm improves).
CREATE TABLE IF NOT EXISTS track (
    id          INTEGER PRIMARY KEY,
    area_id     INTEGER REFERENCES area(id) ON DELETE SET NULL,
    source      TEXT    NOT NULL,             -- 'live' | 'gpx'
    started_at  TEXT,
    ended_at    TEXT
);
CREATE TABLE IF NOT EXISTS track_point (
    track_id  INTEGER NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    seq       INTEGER NOT NULL,
    lng       REAL    NOT NULL,
    lat       REAL    NOT NULL,
    t         TEXT,
    accuracy  REAL,
    PRIMARY KEY (track_id, seq)
);

-- The memory layer: notes / photos pinned to a place (local only).
CREATE TABLE IF NOT EXISTS note (
    id          INTEGER PRIMARY KEY,
    area_id     INTEGER REFERENCES area(id) ON DELETE SET NULL,
    lng         REAL    NOT NULL,
    lat         REAL    NOT NULL,
    body        TEXT,
    photo_path  TEXT,                         -- local file, never uploaded
    created_at  TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_note_area ON note(area_id);
"#;
