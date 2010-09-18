-- sql/1283212129-json_data.sql SQL Migration

SET client_min_messages TO warning;
SET log_min_messages    TO warning;

BEGIN;

CREATE OR REPLACE FUNCTION munge_email(
    email EMAIL
) RETURNS TEXT LANGUAGE plpgsql IMMUTABLE STRICT AS $$
/*

    % SELECT munge_email('foo@bar.com');
     munge_email 
    ─────────────
     bar.com|foo

Munges an email address. This is for use in `mirrors.json`, just to have a bit
of obfuscation. All it does is move the username to the end, separated from
the domain name by a pipe. So "foo@bar.com" becomes "bar.com|foo".

*/
BEGIN
    RETURN split_part(email, '@', 2) || '|' || split_part(email, '@', 1);
END;
$$;

CREATE OR REPLACE FUNCTION get_mirrors_json(
) RETURNS TEXT LANGUAGE sql STABLE STRICT AS $$
/*

    % SELECT get_mirrors_json();
                    get_mirrors_json                 
    ─────────────────────────────────────────────────
     [                                              ↵
        {                                           ↵
           "uri": "http://example.com/pgxn/",       ↵
           "frequency": "hourly",                   ↵
           "location": "Portland, OR, USA",         ↵
           "organization": "Kineticode, Inc.",      ↵
           "timezone": "America/Los_Angeles",       ↵
           "contact": "example.com|pgxn",           ↵
           "bandwidth": "10MBps",                   ↵
           "src": "rsync://master.pgxn.org/pgxn/"   ↵
        },                                          ↵
        {                                           ↵
           "uri": "http://pgxn.example.net/",       ↵
           "frequency": "daily",                    ↵
           "location": "Portland, OR, USA",         ↵
           "organization": "David E. Wheeler",      ↵
           "timezone": "America/Los_Angeles",       ↵
           "contact": "example.net|pgxn",           ↵
           "bandwidth": "Cable",                    ↵
           "src": "rsync://master.pgxn.org/pgxn/",  ↵
           "rsync": "rsync://master.pgxn.org/pgxn/",↵
           "notes": "These be some notes, yo"       ↵
        }                                           ↵
     ]                                              ↵

Returns the JSON for the `mirrors.json` file. The format is an array of JSON
objects. All the required fields will be present, and the optional fields
"rsync" and "notes" will be present only if they have values.

*/
    SELECT E'[\n   ' || array_to_string(ARRAY(
        SELECT E'{\n      ' || array_to_string(ARRAY[
            json_key('uri')          || ': ' || json_value(uri),
            json_key('frequency')    || ': ' || json_value(frequency),
            json_key('location')     || ': ' || json_value(location),
            json_key('organization') || ': ' || json_value(organization),
            json_key('timezone')     || ': ' || json_value(timezone),
            json_key('contact')      || ': ' || json_value(munge_email(contact)),
            json_key('bandwidth')    || ': ' || json_value(bandwidth),
            json_key('src')          || ': ' || json_value(src),
            json_key('rsync')        || ': ' || json_value(rsync, NULL),
            json_key('notes')        || ': ' || json_value(notes, NULL)
        ], E',\n      '
        ) || E'\n   }' FROM mirrors
         ORDER BY created_at
    ), E',\n   ') || E'\n]\n';
$$;

CREATE OR REPLACE FUNCTION by_extension_json(
   dist      TEXT,
   version   SEMVER
) RETURNS TABLE (
    extension CITEXT,
    json      TEXT
) LANGUAGE sql STABLE STRICT AS $$
/*

    % SELECT * FROM by_extension_json('pair', '1.0.0');
     extension │                                     json                                     
    ───────────┼──────────────────────────────────────────────────────────────────────────────
     pair      │ {                                                                           ↵
               │    "stable": "1.0.0",                                                       ↵
               │    "testing": "1.2.0",                                                      ↵
               │    "releases": {                                                            ↵
               │       "1.2.0": { "dist": "pair", "version": "1.2.0", "status": "testing" }, ↵
               │       "1.0.0": { "dist": "pair", "version": "1.0.0" },                      ↵
               │       "0.2.2": { "dist": "pair", "version": "0.0.1", "status": "testing" }  ↵
               │    }                                                                        ↵
               │ }                                                                           ↵
               │ 
     trip      │ {                                                                           ↵
               │    "stable": "0.9.9",                                                       ↵
               │    "testing": "0.9.10",                                                     ↵
               │    "releases": {                                                            ↵
               │       "0.9.10": { "dist": "pair", "version": "1.2.0", "status": "testing" },↵
               │       "0.9.9": { "dist": "pair", "version": "1.0.0" },                      ↵
               │       "0.2.1": { "dist": "pair", "version": "0.0.1", "status": "testing" }  ↵
               │    }                                                                        ↵
               │ }                                                                           ↵
               │ 

Returns a set of extensions and their JSON metadata for a given distribution
version. In the above example, the "pair" and "trip" extensions are both in
the "pair 1.0.0" distribution. Each has data indicating its latest stable,
testing, and unstable versions (as appropriate) and the distribution details
for every released version in descending by extension version number.

*/
    WITH extmap AS (
        SELECT de.extension,
               MAX(CASE d.relstatus WHEN 'stable'   THEN de.ext_version ELSE NULL END) AS stable,
               MAX(CASE d.relstatus WHEN 'testing'  THEN de.ext_version ELSE NULL END) AS testing,
               MAX(CASE d.relstatus WHEN 'unstable' THEN de.ext_version ELSE NULL END) AS unstable,
               array_agg(
                   json_key(de.ext_version) || ': { "dist": ' || json_value(d.name)
                   || ', "version": ' || json_value(d.version)
                   || CASE d.relstatus WHEN 'stable' THEN '' ELSE ', "status": ' || json_value(d.relstatus::text) END
                   || ' }'
               ORDER BY de.ext_version USING >) AS releases
          FROM distributions d
          JOIN distribution_extensions de
            ON d.name     = de.distribution
           AND d.version  = de.dist_version
         GROUP BY de.extension
    )
    SELECT e.extension, E'{\n   '
        || CASE WHEN stable   IS NULL THEN '' ELSE '"stable": '   || json_value(stable)   || E',\n   ' END
        || CASE WHEN testing  IS NULL THEN '' ELSE '"testing": '  || json_value(testing)  || E',\n   ' END
        || CASE WHEN unstable IS NULL THEN '' ELSE '"unstable": ' || json_value(unstable) || E',\n   ' END
        || E'"releases": {\n      ' || array_to_string(releases, E',\n      ') || E'\n   }\n}\n'
      FROM extmap e
      JOIN distribution_extensions de ON e.extension = de.extension
     WHERE de.distribution = $1
       AND de.dist_version = $2;
$$;

CREATE OR REPLACE VIEW distribution_versions AS
SELECT name AS distribution,
       '[' || string_agg(
           CASE relstatus WHEN 'stable'
           THEN '"' || version || '"'
           ELSE NULL
       END, ', ' ORDER BY version USING >) || ']' AS stable,
       '[' || string_agg(
           CASE relstatus
           WHEN 'testing'
           THEN '"' || version || '"'
           ELSE NULL
       END, ', ' ORDER BY version USING >) || ']' AS testing,
       '[' || string_agg(
           CASE relstatus
           WHEN 'unstable'
           THEN '"' || version || '"'
           ELSE NULL
       END, ', ' ORDER BY version USING >) || ']' AS unstable
  FROM distributions
 GROUP BY name;

GRANT SELECT ON distribution_versions TO pgxn;

CREATE OR REPLACE FUNCTION by_dist_json(
   dist      TEXT
) RETURNS TEXT LANGUAGE sql STABLE STRICT AS $$
/*

    % SELECT * FROM by_dist_json('pair');
                  by_dist_json               
    ─────────────────────────────────────────
     {                                      ↵
        "name": "pair",                     ↵
        "releases": {                       ↵
           "stable": ["1.0.0"],             ↵
           "testing": ["1.2.0", "0.0.1"]    ↵
        }                                   ↵
     }                                      ↵

Returns a JSON string describing a distribution, including all of its released
versions.

*/
    SELECT E'{\n   "name": ' || json_value(distribution)
           || E',\n   "releases": {\n      '
           || array_to_string(ARRAY[
               '"stable": '   || stable,
               '"testing": '  || testing,
               '"unstable": ' || unstable
           ], E',\n      ') || E'\n   }\n}\n'
      FROM distribution_versions
     WHERE distribution = $1;
$$;

CREATE OR REPLACE FUNCTION by_tag_json(
   dist      TEXT,
   version   SEMVER
) RETURNS TABLE (
    tag  CITEXT,
    json TEXT
) LANGUAGE sql STABLE STRICT AS $$
/*

    % SELECT * FROM by_tag_json('pgtap', '0.0.1');
       tag   │                  json                  
    ─────────┼────────────────────────────────────────
     schema  │ {                                     ↵
             │    "tag": "schema",                   ↵
             │    "releases": {                      ↵
             │       "pair": {                       ↵
             │          "stable": ["1.0.0"],         ↵
             │          "testing": ["1.2.0", "0.0.1"]↵
             │       },                              ↵
             │       "pgtap": {                      ↵
             │          "testing": ["0.0.1"]         ↵
             │       }                               ↵
             │    }                                  ↵
             │ }                                     ↵
             │ 
     testing │ {                                     ↵
             │    "tag": "testing",                  ↵
             │    "releases": {                      ↵
             │       "pgtap": {                      ↵
             │          "testing": ["0.0.1"]         ↵
             │       }                               ↵
             │    }                                  ↵
             │ }                                     ↵
             │ 

For a given distribution and version, returns a set of tags and the JSON to
describe them. In this example, pgtap 0.0.1 has two tags. The tag "testing" is
only associated with pgtap 0.0.1. The tag "schema", on the other hand, is
associcated with three versions of the "pair" distribution, as well.

*/
    SELECT tag, E'{\n   "tag": ' || json_value(tag) || E',\n   "releases": {\n'
           || string_agg(
               DISTINCT '      "' || dv.distribution
                   || E'": {\n         ' ||  array_to_string(ARRAY[
                       '"stable": '   || stable,
                       '"testing": '  || testing,
                       '"unstable": ' || unstable
                   ], E',\n         ') || E'\n      }',
              E',\n')
           || E'\n   }\n}\n'
      FROM distribution_tags dt
      JOIN distribution_versions dv
        ON dt.distribution = dv.distribution
     WHERE dt.tag IN (
        SELECT tag
          FROM distribution_tags
         WHERE distribution = $1
           AND version      = $2
     )
     GROUP BY tag;
$$;

CREATE OR REPLACE FUNCTION by_owner_json(
   owner LABEL
) RETURNS TEXT LANGUAGE sql STABLE STRICT AS $$
/*

    % SELECT by_owner_json('theory');
                  by_owner_json               
    ──────────────────────────────────────────
     {                                       ↵
        "nickname": "theory",                ↵
        "name": "David E. Wheeler",          ↵
        "email": "justatheory@pgxn.org",     ↵
        "uri": "http://www.justatheory.com/",↵
        "releases": {                        ↵
           "pair": {                         ↵
              "stable": ["1.0.0"],           ↵
              "testing": ["0.0.1"]           ↵
           },                                ↵
           "pgtap": {                        ↵
              "testing": ["0.0.1"]           ↵
           }                                 ↵
        }                                    ↵
     }                                       ↵

Returns a JSON string describing the given user, including all of the
distributions the user owns. The included distribution versions are only the
versions owned by the user; if someone else uploaded a different version of
the distribution, that version will not be owned by this user and thus not
included in the JSON.

*/
    WITH dv AS (
        SELECT name AS distribution, owner,
       '[' || string_agg(
           CASE relstatus WHEN 'stable'
           THEN '"' || version || '"'
           ELSE NULL
       END, ', ' ORDER BY version USING >) || ']' AS stable,
       '[' || string_agg(
           CASE relstatus
           WHEN 'testing'
           THEN '"' || version || '"'
           ELSE NULL
       END, ', ' ORDER BY version USING >) || ']' AS testing,
       '[' || string_agg(
           CASE relstatus
           WHEN 'unstable'
           THEN '"' || version || '"'
           ELSE NULL
       END, ', ' ORDER BY version USING >) || ']' AS unstable
         FROM distributions
        GROUP BY name, owner
    )
    SELECT E'{\n   ' || array_to_string(ARRAY[
        '"nickname": ' || json_value(u.nickname),
        '"name": '     || json_value(u.full_name),
        '"email": '    || json_value(u.email),
        '"uri": '      || json_value(uri, NULL)
    ], E',\n   ') || COALESCE(E',\n   "releases": {\n' ||
           string_agg(
                 '      "' || dv.distribution
                   || E'": {\n         ' ||  array_to_string(ARRAY[
                       '"stable": '   || stable,
                       '"testing": '  || testing,
                       '"unstable": ' || unstable
                   ], E',\n         ') || E'\n      }',
              E',\n')
           || E'\n   }\n}\n', E'\n}\n')
      FROM users u
      LEFT JOIN dv ON u.nickname = dv.owner
     WHERE u.nickname = $1
     GROUP BY u.nickname, u.full_name, u.email, u.uri;
$$;

COMMIT;
