CREATE OR REPLACE FUNCTION check_versions(
    dist     TERM,
    version  SEMVER,
    provided TEXT[][]
) RETURNS VOID LANGUAGE plpgsql STRICT SECURITY DEFINER AS $$
DECLARE
    -- Parse and normalize the metadata.
    prev_version SEMVER;
    versions     TEXT[];
BEGIN
    -- Make sure the version is earlier than previous releases.
    SELECT MAX(distributions.version) INTO prev_version
      FROM distributions
     WHERE name = dist;
    IF version < prev_version THEN
       RAISE EXCEPTION 'Version % is less than previous version %', version, prev_version;
    END IF;

    -- Same goes for extensions.
    versions := ARRAY(
        SELECT de.extension || ' v' || provided[i][2]
               || ' < v' || MAX(de.ext_version)
          FROM distribution_extensions de
          JOIN generate_subscripts(provided, 1) i
            ON de.extension = provided[i][1]
           AND de.ext_version > provided[i][2]::semver
         GROUP BY de.extension, provided[i][2]
    );
    IF array_length(versions, 1) > 0 THEN
       RAISE EXCEPTION E'One or more extension versions are less than previous versions:\n  %', array_to_string(versions, E'\n  ');
    END IF;

    RETURN;
END;
$$;

-- Disallow end-user from using this function.
REVOKE ALL ON FUNCTION check_versions(TERM, SEMVER, TEXT[][]) FROM PUBLIC;

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

See the [PGXN Meta Spec](http://pgxn.org/spec/)
for the complete list of specified keys.

With this data, `add_distribution()` does the following things:

* Parses the JSON string and validates that all required keys are present.
  Throws an exception if they're not.

* Creates a new metadata structure and stores all the required and many of the
  optional meta spec keys, as well as the SHA1 of the distribution file, the
  release date, and the user's nickname.

* Normalizes all of the version numbers found in the metadata into compliant
  semantic version strings. See
  [`SemVer->normal`](http://search.cpan.org/dist/SemVer/lib/SemVer.pm#declare)
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
    perform check_versions(distmeta.name, distmeta.version, distmeta.provided);

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

