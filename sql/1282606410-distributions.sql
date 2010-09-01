-- sql/1282606410-distributions.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TYPE relstatus AS ENUM(
    'stable',
    'testing',
    'unstable'
);

CREATE TABLE distributions (
    name        CITEXT      NOT NULL,
    version     SEMVER      NOT NULL,
    abstract    TEXT        NOT NULL DEFAULT '',
    description TEXT        NOT NULL DEFAULT '',
    relstatus   RELSTATUS   NOT NULL DEFAULT 'stable',
    owner       LABEL       NOT NULL REFERENCES users(nickname),
    sha1        CITEXT      NOT NULL,
    meta        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (name, version)
);

CREATE TABLE distribution_tags (
    distribution CITEXT,
    version      SEMVER,
    tag          CITEXT,
    PRIMARY KEY (distribution, version, tag),
    FOREIGN KEY (distribution, version) REFERENCES distributions(name, version)
);

CREATE INDEX idx_distribution_tags_tag ON distribution_tags(tag);

COMMIT;
