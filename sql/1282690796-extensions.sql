-- sql/1282690796-extensions.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE TABLE extensions (
    name  CITEXT           PRIMARY KEY,
    owner LABEL            NOT NULL REFERENCES users(nickname),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE coowners (
    extension  CITEXT      NOT NULL REFERENCES extensions(name),
    nickname   LABEL       NOT NULL REFERENCES users(nickname),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (extension, nickname)
);
    
CREATE TABLE distribution_extensions (
    extension    CITEXT NOT NULL REFERENCES extensions(name),
    ext_version  SEMVER NOT NULL,
    distribution CITEXT NOT NULL,
    dist_version SEMVER NOT NULL,
    PRIMARY KEY (extension, ext_version),
    FOREIGN KEY (distribution, dist_version) REFERENCES distributions(name, version)
);

COMMIT;
