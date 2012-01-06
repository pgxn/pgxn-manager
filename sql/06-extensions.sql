-- sql/06-extensions.sql SQL Migration

SET client_min_messages TO warning;

BEGIN;

CREATE TABLE extensions (
    name       TERM        PRIMARY KEY,
    owner      LABEL       NOT NULL REFERENCES users(nickname),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

GRANT SELECT ON extensions TO pgxn;

CREATE TABLE coowners (
    extension  TERM        NOT NULL REFERENCES extensions(name),
    nickname   LABEL       NOT NULL REFERENCES users(nickname),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (extension, nickname)
);
    
CREATE TABLE distribution_extensions (
    extension    TERM   NOT NULL REFERENCES extensions(name),
    ext_version  SEMVER NOT NULL,
    abstract     TEXT   NOT NULL,
    distribution TERM   NOT NULL,
    dist_version SEMVER NOT NULL,
    PRIMARY KEY (extension, ext_version, distribution, dist_version),
    FOREIGN KEY (distribution, dist_version) REFERENCES distributions(name, version)
);

GRANT SELECT ON distribution_extensions TO pgxn;

COMMIT;
