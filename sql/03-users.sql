-- sql/03-users.sql SQL Migration

SET client_min_messages TO warning;

BEGIN;

CREATE TYPE status AS ENUM(
    'new',
    'active',
    'inactive',
    'deleted'
);

CREATE TABLE users (
    nickname   LABEL       PRIMARY KEY,
    password   TEXT        NOT NULL,
    full_name  TEXT        NOT NULL,
    email      EMAIL       NOT NULL UNIQUE,
    uri        URI         NULL,
    twitter    CITEXT      NOT NULL DEFAULT '',
    why        TEXT        NOT NULL DEFAULT '',
    status     STATUS      NOT NULL DEFAULT 'new',
    set_by     LABEL       NOT NULL REFERENCES users(nickname),
    is_admin   BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT SELECT ON users TO pgxn;

COMMIT;
