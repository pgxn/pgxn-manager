CREATE OR REPLACE FUNCTION check_dist_version (
    dist     TERM,
    version  SEMVER
) RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
/*

    SELECT check_dist_version('pair', '1.2.0');
    check_dist_version
    --------------------


Checks to see if a distribution name and version is allowed to be created or
updated. Returns no value if the version is allowed, and throws an exception if
it is not. A new version of a distribution can be created or updated if any of
the following rules apply to the distribution:

*   No other version exists
*   The new version is greater than or equal to all existing versions (x.y.z)
*   The new version is greater than or equal to all versions with the same major
    and minor parts (x.y)
*   The new version is greater than or equal to all versions with the same major
    parts (x)

The first case applies if it's a new distribution name.

The second is the usual expected case, where the new version is the highest

The third case applies for updating an existing minor version. For example, if
there are existing versions 1.2.3 and 1.4.2, a new version 1.2.4 would be
allowed, but not 1.2.2 or 1.3.0.

The fourth case applies for updating an existing major version. For example, if
there are existing versions 1.2.6 and 2.0.4, a new version 1.3.0 would be
allowed, but not 0.10.0.

*/
DECLARE
    max_version SEMVER;
    min_version SEMVER;
    maj_version SEMVER;
BEGIN
    -- Make sure the version is greater than previous release versions.
    -- Allow lower version if higher than existing minor version or higher than existing major version.
    SELECT MAX(d.version),
           MAX(d.version) FILTER (WHERE get_semver_major(d.version) = get_semver_major(check_dist_version.version) AND get_semver_minor(d.version) = get_semver_minor(check_dist_version.version)),
           MAX(d.version) FILTER (WHERE get_semver_major(d.version) = get_semver_major(check_dist_version.version))
      INTO max_version, min_version, maj_version
      FROM distributions d
     WHERE d.name = dist;

    -- Allow if no previous, or version is higher than any x.y.z version.
    IF max_version IS NULL OR version >= max_version THEN RETURN; END IF;

    -- Allow if higher than existing instance of same x.y version.
    IF min_version IS NOT NULL THEN
        IF version >= min_version THEN RETURN; END IF;
        RAISE EXCEPTION 'Distribution “% %” version not greater than previous minor release “% %”',
              dist, version, dist, min_version;
    END IF;

    -- Allow if higher than existing instance of same x version.
    IF maj_version IS NOT NULL THEN
        IF version >= maj_version THEN RETURN; END IF;
        RAISE EXCEPTION 'Distribution “% %” version not greater than previous major release “% %”',
              dist, version, dist, maj_version;
    END IF;

    -- No previous major or minor found and not higher than anything else, so bail.
    RAISE EXCEPTION 'Distribution “% %” version not greater than previous release “% %”',
          dist, version, dist, max_version;
END;
$$;

-- Disallow end-user from using this function.
REVOKE ALL ON FUNCTION check_dist_version(TERM, SEMVER) FROM PUBLIC;

-- Drop old funtions.
SET client_min_messages TO warning;
DROP FUNCTION IF EXISTS check_prev_versions(TEXT[][], TIMESTAMPTZ);
DROP FUNCTION IF EXISTS check_later_versions(TEXT[][], TIMESTAMPTZ);
RESET client_min_messages;

CREATE OR REPLACE FUNCTION add_distribution(
    nick LABEL,
    sha1 TEXT,
    meta TEXT
) RETURNS TABLE (
    template TEXT,
    subject  TEXT,
    json     TEXT
) LANGUAGE plpgsql STRICT SECURITY DEFINER AS $$
/*

    % SELECT * FROM add_distribution('theory', 'ebf381e2e1e5767fb068d1c4423a9d9f122c2dc6', '{
        "name": "pair",
        "version": "0.0.01",
        "license": "postgresql",
        "maintainer": "theory",
        "abstract": "Ordered pair",
        "tags": ["ordered pair", "key value"],
        "provides": {
            "pair": {
                "file": "pair.sql.in",
                "version": "0.02.02",
                "abstract": "A key/value data type"
            },
            "trip": {
                "file": "trip.sql.in",
                "version": "0.02.01",
                "abstract": "A triple data type"
            }
        },
        "release_status": "testing"
    }');
    
     template  │   subject    │                                 json                                 
    ───────────┼──────────────┼──────────────────────────────────────────────────────────────────────
     meta      │ pair         │ {                                                                   ↵
               │              │    "name": "pair",                                                  ↵
               │              │    "abstract": "Ordered pair",                                      ↵
               │              │    "version": "0.0.1",                                              ↵
               │              │    "maintainer": "theory",                                          ↵
               │              │    "date": "2011-03-15T16:44:26Z",                                  ↵
               │              │    "release_status": "testing",                                     ↵
               │              │    "user": "theory",                                                ↵
               │              │    "sha1": "ebf381e2e1e5767fb068d1c4423a9d9f122c2dc6",              ↵
               │              │    "license": "postgresql",                                         ↵
               │              │    "provides": {                                                    ↵
               │              │       "pair": {                                                     ↵
               │              │          "file": "pair.sql.in",                                     ↵
               │              │          "version": "0.2.2",                                        ↵
               │              │          "abstract": "A key/value data type"                        ↵
               │              │       },                                                            ↵
               │              │       "trip": {                                                     ↵
               │              │          "file": "trip.sql.in",                                     ↵
               │              │          "version": "0.2.1"                                         ↵
               │              │          "abstract": "A triple data type"                           ↵
               │              │       }                                                             ↵
               │              │    },                                                               ↵
               │              │    "tags": ["ordered pair", "key value"]                            ↵
               │              │ }                                                                   ↵
               │              │ 
     dist      │ pair         │ {                                                                   ↵
               │              │    "name": "pair",                                                  ↵
               │              │    "releases": {                                                    ↵
               │              │       "testing": ["0.0.1"]                                          ↵
               │              │    }                                                                ↵
               │              │ }                                                                   ↵
               │              │ 
     extension │ pair         │ {                                                                   ↵
               │              │    "extension": "pair",                                             ↵
               │              │    "latest": "testing",                                             ↵
               │              │    "testing":  { "dist": "pair", "version": "0.0.1" },              ↵
               │              │    "versions": {                                                    ↵
               │              │       "0.2.2": [                                                    ↵
               │              │          { "dist": "pair", "version": "0.0.1", "status": "testing" }↵
               │              │       ]                                                             ↵
               │              │    }                                                                ↵
               │              │ }                                                                   ↵
               │              │ 
     extension │ trip         │ {                                                                   ↵
               │              │    "extension": "trip",                                             ↵
               │              │    "latest": "testing",                                             ↵
               │              │    "testing":  { "dist": "pair", "version": "0.0.1" },              ↵
               │              │    "versions": {                                                    ↵
               │              │       "0.2.1": [                                                    ↵
               │              │          { "dist": "pair", "version": "0.0.1", "status": "testing" }↵
               │              │       ]                                                             ↵
               │              │    }                                                                ↵
               │              │ }                                                                   ↵
               │              │ 
     user      │ theory       │ {                                                                   ↵
               │              │    "nickname": "theory",                                            ↵
               │              │    "name": "",                                                      ↵
               │              │    "email": "theory@pgxn.org",                                      ↵
               │              │    "releases": {                                                    ↵
               │              │       "pair": {                                                     ↵
               │              │          "testing": ["0.0.1"]                                       ↵
               │              │       }                                                             ↵
               │              │    }                                                                ↵
               │              │ }                                                                   ↵
               │              │ 
     tag       │ ordered pair │ {                                                                   ↵
               │              │    "tag": "ordered pair",                                           ↵
               │              │    "releases": {                                                    ↵
               │              │       "pair": {                                                     ↵
               │              │          "testing": [ "0.0.1" ]                                     ↵
               │              │       }                                                             ↵
               │              │    }                                                                ↵
               │              │ }                                                                   ↵
               │              │ 
     tag       │ key value    │ {                                                                   ↵
               │              │    "tag": "key value",                                              ↵
               │              │    "releases": {                                                    ↵
               │              │       "pair": {                                                     ↵
               │              │          "testing": [ "0.0.1" ]                                     ↵
               │              │       }                                                             ↵
               │              │    }                                                                ↵
               │              │ }                                                                   ↵
               │              │                                                                     ↵
     stats     | dist         | {                                                                   ↵
               │              │    "count": 92,                                                     ↵
               │              │    "releases": 345,                                                 ↵
               │              │    "recent": [                                                      ↵
               │              │       {                                                             ↵
               │              │          "dist": "pair",                                            ↵
               │              │          "version": "0.0.1",                                        ↵
               │              │          "abstract": "Ordered pair",                                ↵
               │              │          "date": "2011-03-15T16:44:26Z",                            ↵
               │              │          "user": "theory",                                          ↵
               │              │          "user_name": "David Wheeler"                               ↵
               │              │       },                                                            ↵
               │              │       {                                                             ↵
               │              │           "dist": "pg_french_datatypes",                            ↵
               │              │           "version": "0.1.1",                                       ↵
               │              │           "abstract": "french-centric data type",                   ↵
               │              │           "date": "2011-01-30T16:51:16Z",                           ↵
               │              │           "user": "daamien",                                        ↵
               │              │           "user_name": "damien clochard"                            ↵
               │              │       }                                                             ↵
               │              │    ]                                                                ↵
               │              │ }                                                                   ↵
     stats     │ extension    │                                                                     ↵
               │              │ {                                                                   ↵
               │              │    "count": 125,                                                    ↵
               │              │    "recent": [                                                      ↵
               │              │       {                                                             ↵
               │              │          "extension": "pair",                                       ↵
               │              │          "abstract": "Ordered pair",                                ↵
               │              │          "ext_version": "0.0.1",                                    ↵
               │              │          "dist": "pair",                                            ↵
               │              │          "version": "0.0.1",                                        ↵
               │              │          "date": "2011-03-15T16:44:26Z",                            ↵
               │              │          "user": "theory",                                          ↵
               │              │          "user_name": "David Wheeler"                               ↵
               │              │       },                                                            ↵
               │              │       {                                                             ↵
               │              │          "extension": "pg_french_datatypes",                        ↵
               │              │          "abstract": "french-centric data type",                    ↵
               │              │          "ext_version": "0.1.1",                                    ↵
               │              │          "dist": "pg_french_datatypes",                             ↵
               │              │          "version": "0.1.1",                                        ↵
               │              │          "date": "2011-01-30T16:51:16Z",                            ↵
               │              │          "user": "daamien",                                         ↵
               │              │          "user_name": "damien clochard"                             ↵
               │              │       }                                                             ↵
               │              │    ]                                                                ↵
               │              │ }                                                                   ↵
               │              │                                                                     ↵
     stats     │ user         │ {                                                                   ↵
               │              │    "count": 256,                                                    ↵
               │              │    "prolific": [                                                    ↵
               │              │       {"nickname": "theory", "dists": 3, "releases": 4},            ↵
               │              │       {"nickname": "daamien", "dists": 1, "releases": 2},           ↵
               │              │       {"nickname": "umitanuki", "dists": 1, "releases": 1}          ↵
               │              │    ]                                                                ↵
               │              │ }                                                                   ↵
               │              │                                                                     ↵
     stats     │ tag          │ {                                                                   ↵
               │              │    "count": 212,                                                    ↵
               │              │    "popular": [                                                     ↵
               │              │       {"tag": "data types", "dists": 4},                            ↵
               │              │       {"tag": "key value", "dists": 2},                             ↵
               │              │       {"tag": "france", "dists": 1},                                ↵
               │              │       {"tag": "key value pair", "dists": 1}                         ↵
               │              │     ]                                                               ↵
               │              │ }                                                                   ↵
               │              │                                                                     ↵
     stats     │ summary      │ {                                                                   ↵
               │              │    "dists": 92,                                                     ↵
               │              │    "releases": 345,                                                 ↵
               │              │    "extensions": 125,                                               ↵
               │              │    "users": 256,                                                    ↵
               │              │    "tags": 112,                                                     ↵
               │              │    "mirrors": 8                                                     ↵
               │              │ }                                                                   ↵
               │              │                                                                     ↵

Creates a new distribution, returning all of the JSON that needs to be written
to the mirror in order for the distribution to be indexed. The nickname of the
uploading user must be passed as the first argument. The SHA1 of the
distribution file must be passed as the second argument. All other metadata is
parsed from the JSON string, which should contain the complete contents of the
distribution's `META.json` file. The required keys in the JSON metadata are:

name
: The name of the extension.

version
: The extension version string. Will be normalized by `clean_semver()`.

license
: The license or licenses.

maintainer
: The distribution maintainer or maintainers.

abstract
: Short description of the distribution.

See the [PGXN Meta Spec](https://pgxn.org/spec/)
for the complete list of specified keys.

With this data, `add_distribution()` does the following things:

* Parses the JSON string and validates that all required keys are present.
  Throws an exception if they're not.

* Creates a new metadata structure and stores all the required and many of the
  optional meta spec keys, as well as the SHA1 of the distribution file, the
  release date, and the user's nickname.

* Normalizes all of the version numbers found in the metadata into compliant
  semantic version strings. See
  [`SemVer->normal`](https://metacpan.org/pod/distribution/SemVer/lib/SemVer.pm#normal)
  for details on how non-compliant version strings are converted. Versions
  that cannot be normalized will trigger an exception.

* Specifies that the provided extension is the same as the distribution name
  and version if no "provides" metadata is present in the distribution
  metadata.

* Validates that the uploading user is owner or co-owner of all provided
  extensions. If no one is listed as owner of one or more included extensions,
  the user will be assigned ownership. If the user is not owner or co-owner of
  any included extensions, an exception will be thrown.

* Validates that the release version is greater than in any previous release,
  and that all extension versions are greater than or equal to versions in any
  previous releases.

* Inserts the distribution data into the `distributions` table.

* Inserts records for all included extensions into the
  `distribution_extensions` table.

* Inserts records for all associated tags into the `distribution_tags` table.

Once all this work is done, `add_distribution()` returns a relation with the
following columns:

template
: Name of a mirror URI template.

subject
: The subject of the metadata to be written, such as the name of a
  distribution, extension, user, tag, or statistics.

json
: The JSON-formatted metadata for the subject, which the application should
  write to the fie specified by the template.

*/
DECLARE
    -- Parse and normalize the metadata.
    distmeta     RECORD;
BEGIN
    distmeta := setup_meta(nick, sha1, meta);

    -- Check permissions for provided extensions.
    IF NOT record_ownership(nick, ARRAY(
        SELECT distmeta.provided[i][1] FROM generate_subscripts(distmeta.provided, 1) AS i
    )) THEN
        RAISE EXCEPTION 'User “%” does not own all provided extensions', nick;
    END IF;

    -- Make sure the versions are okay.
    PERFORM check_dist_version(distmeta.name, distmeta.version);

    -- Create the distribution.
    BEGIN
        INSERT INTO distributions (name, version, relstatus, abstract, description, sha1, creator, meta)
        VALUES (distmeta.name, distmeta.version, COALESCE(distmeta.relstatus, 'stable'),
                distmeta.abstract, COALESCE(distmeta.description, ''), sha1, nick, distmeta.json);
    EXCEPTION WHEN unique_violation THEN
       RAISE EXCEPTION 'Distribution “% %” already exists', distmeta.name, distmeta.version;
    END;

    -- Record the extensions in this distribution.
    INSERT INTO distribution_extensions (extension, ext_version, abstract, distribution, dist_version)
    SELECT distmeta.provided[i][1], distmeta.provided[i][2]::semver, distmeta.provided[i][3], distmeta.name, distmeta.version
      FROM generate_subscripts(distmeta.provided, 1) AS i;

    -- Record the tags for this distribution.
    INSERT INTO distribution_tags (distribution, version, tag)
    SELECT DISTINCT distmeta.name, distmeta.version, tag
      FROM unnest(distmeta.tags) AS tag;

    RETURN QUERY
        SELECT 'meta'::TEXT, LOWER(distmeta.name::TEXT), distmeta.json
    UNION
        SELECT 'dist', LOWER(distmeta.name::TEXT), dist_json(distmeta.name)
    UNION
        SELECT 'extension', * FROM extension_json(distmeta.name, distmeta.version)
    UNION
        SELECT 'user', LOWER(nick), user_json(nick)
    UNION
        SELECT 'tag', * FROM tag_json(distmeta.name, distmeta.version)
    UNION
        SELECT 'stats', * FROM all_stats_json()
    ;
END;
$$;

CREATE OR REPLACE FUNCTION update_distribution(
    nick LABEL,
    sha1 TEXT,
    meta TEXT
) RETURNS TABLE (
    template TEXT,
    subject  TEXT,
    json     TEXT
) LANGUAGE plpgsql STRICT SECURITY DEFINER AS $$
/*

Exactly like `add_distribution()`, with the same arguments and rules, but
updates an existing distribution, rather than creating a new one. This may be
useful if the format of the generated `META.json` file changes: just call this
method for all existing distributions to have then reindexed with the new
format.

Note that, for all included extensions, `nick` must have ownership or no one
must, in which case the user will be given ownership. This might be an issue
when re-indexing a distribution containing extensions that the user owned at
the time the distribution was released, but no longer does. In that case,
you'll probably need to grant the user temporary co-ownership of all
extensions, re-index, and then revoke.

*/
DECLARE
    distmeta record;
BEGIN
    -- Parse and normalize the metadata.
    distmeta := setup_meta(nick, sha1, meta);

    -- Check permissions for provided extensions.
    IF NOT record_ownership(nick, ARRAY(
        SELECT distmeta.provided[i][1] FROM generate_subscripts(distmeta.provided, 1) AS i
    )) THEN
        RAISE EXCEPTION 'User “%” does not own all provided extensions', nick;
    END IF;

    -- Update the distribution.
    UPDATE distributions
       SET relstatus   = COALESCE(distmeta.relstatus, 'stable'),
           abstract    = distmeta.abstract,
           description = COALESCE(distmeta.description, ''),
           sha1        = update_distribution.sha1,
           creator     = nick,
           meta        = distmeta.json
     WHERE name        = distmeta.name
       AND version     = distmeta.version;

    IF NOT FOUND THEN
       RAISE EXCEPTION 'Distribution “% %” does not exist', distmeta.name, distmeta.version;
    END IF;

    -- Update the extensions in this distribution.
    UPDATE distribution_extensions de
       SET abstract     = distmeta.provided[i][3]
      FROM generate_subscripts(distmeta.provided, 1) AS i
     WHERE de.extension    = distmeta.provided[i][1]
       AND de.ext_version  = distmeta.provided[i][2]::semver
       AND de.distribution = distmeta.name
       AND de.dist_version = distmeta.version;

    -- Insert missing extensions.
    INSERT INTO distribution_extensions (
           extension,
           ext_version,
           abstract,
           distribution,
           dist_version
    )
    SELECT distmeta.provided[i][1],
           distmeta.provided[i][2]::semver,
           distmeta.provided[i][3],
           distmeta.name,
           distmeta.version
      FROM generate_subscripts(distmeta.provided, 1) AS i
      LEFT JOIN distribution_extensions de
        ON de.extension    = distmeta.provided[i][1]
       AND de.ext_version  = distmeta.provided[i][2]::semver
       AND de.distribution = distmeta.name
       AND de.dist_version = distmeta.version
     WHERE de.extension    IS NULL;

    -- Delete unwanted extensions.
    DELETE FROM distribution_extensions
     USING distribution_extensions de
      LEFT JOIN generate_subscripts(distmeta.provided, 1) AS i
        ON de.extension                         = distmeta.provided[i][1]
       AND de.extension                         = distmeta.provided[i][1]
       AND de.ext_version                       = distmeta.provided[i][2]::semver
     WHERE de.distribution                      = distmeta.name
       AND de.dist_version                      = distmeta.version
       AND distribution_extensions.extension    = de.extension
       AND distribution_extensions.ext_version  = de.ext_version
       AND distribution_extensions.distribution = de.distribution
       AND distribution_extensions.dist_version = de.dist_version
       AND distmeta.provided[i][1] IS NULL;

    -- Insert missing tags.
    INSERT INTO distribution_tags (distribution, version, tag)
    SELECT DISTINCT distmeta.name, distmeta.version, tags.tag
      FROM unnest(distmeta.tags) AS tags(tag)
      LEFT JOIN distribution_tags dt
        ON dt.distribution = distmeta.name
       AND dt.version      = distmeta.version
       AND dt.tag          = tags.tag
     WHERE dt.tag          IS NULL;

    -- Remove unwanted tags.
    DELETE FROM distribution_tags
     USING distribution_tags dt
      LEFT JOIN unnest(distmeta.tags) AS tags(tag)
        ON dt.tag                         = tags.tag
     WHERE dt.distribution                = distmeta.name
       AND dt.version                     = distmeta.version
       AND tags.tag                       IS NULL
       AND distribution_tags.distribution = dt.distribution
       AND distribution_tags.version      = dt.version
       AND distribution_tags.tag          = dt.tag;

    RETURN QUERY
        SELECT 'meta'::TEXT, LOWER(distmeta.name::TEXT), distmeta.json
    UNION
        SELECT 'dist', LOWER(distmeta.name::TEXT), dist_json(distmeta.name)
    UNION
        SELECT 'extension', * FROM extension_json(distmeta.name, distmeta.version)
    UNION
        SELECT 'user', LOWER(nick), user_json(nick)
    UNION
        SELECT 'tag', * FROM tag_json(distmeta.name, distmeta.version)
    UNION
        SELECT 'stats', * FROM all_stats_json()
    ;
END;
$$;
