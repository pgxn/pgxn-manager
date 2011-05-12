-- sql/05-distributions.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TYPE relstatus AS ENUM(
    'stable',
    'testing',
    'unstable'
);

CREATE TABLE distributions (
    name        CITEXT      NOT NULL CHECK (
         length(name) >= 2 AND name !~ '[[:space:][:blank:][:cntrl:]/\\]'
    ),
    version     SEMVER      NOT NULL,
    abstract    TEXT        NOT NULL DEFAULT '',
    description TEXT        NOT NULL DEFAULT '',
    relstatus   RELSTATUS   NOT NULL DEFAULT 'stable',
    creator     LABEL       NOT NULL REFERENCES users(nickname),
    sha1        CITEXT      NOT NULL,
    meta        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (name, version)
);

GRANT SELECT ON distributions TO pgxn;

CREATE TABLE distribution_tags (
    distribution CITEXT,
    version      SEMVER,
    tag          CITEXT,
    PRIMARY KEY (distribution, version, tag),
    FOREIGN KEY (distribution, version) REFERENCES distributions(name, version)
);

CREATE INDEX idx_distribution_tags_tag ON distribution_tags(tag);
GRANT SELECT ON distribution_tags TO pgxn;

COMMIT;
