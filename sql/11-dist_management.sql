-- sql/11-add_distribution.sql SQL Migration

CREATE OR REPLACE FUNCTION setup_meta(
    IN  nick        LABEL,
    IN  sha1        TEXT,
    IN  json        TEXT,
    OUT name        TERM,
    OUT version     SEMVER,
    OUT relstatus   RELSTATUS,
    OUT abstract    TEXT,
    OUT description TEXT,
    OUT provided    TEXT[][],
    OUT tags        CITEXT[],
    OUT json        TEXT
) LANGUAGE plperl IMMUTABLE AS $$
    my $idx_meta  = { user => shift, sha1 => shift };
    my $dist_meta = JSON::XS->new->utf8(0)->decode(shift);

    # Check required keys.
    for my $key (qw(name version license maintainer abstract provides)) {
        $idx_meta->{$key} = $dist_meta->{$key} or elog(
            ERROR, qq{Metadata is missing the required “$key” key}
        );
    }

    # Grab optional fields.
    for my $key (qw(description tags no_index prereqs release_status resources)) {
        $idx_meta->{$key} = $dist_meta->{$key} if exists $dist_meta->{$key};
    }

    # Set default release status.
    $idx_meta->{release_status} ||= 'stable';

    # Normalize version string.
    $idx_meta->{version} = SemVer->declare($idx_meta->{version})->normal;

    # Set the date; use an existing one if it's available.
    $idx_meta->{date} = spi_exec_query(sprintf
        q{SELECT utc_date(COALESCE(
            (SELECT created_at FROM distributions WHERE name = %s AND version = %s),
            NOW()
        ))},
        quote_literal($idx_meta->{name}),
        quote_literal($idx_meta->{version})
    )->{rows}[0]{utc_date};

    # Normalize "prereq" version strings.
    if (my $prereqs = $idx_meta->{prereqs}) {
        for my $phase (values %{ $prereqs }) {
            for my $type ( values %{ $phase }) {
                for my $prereq (keys %{ $type }) {
                    $type->{$prereq} = SemVer->declare($type->{$prereq})->normal;
                }
            }
        }
    }

    my $provides = $idx_meta->{provides};
    # Normalize "provides" version strings.
    for my $ext (values %{ $provides }) {
        $ext->{version} = SemVer->declare($ext->{version})->normal;
    }

    # XXX Normalize maintainers, licenses, other fields?

    # Recreate the JSON.
    my $encoder = JSON::XS->new->utf8(0)->space_after->allow_nonref->indent->canonical;
    my $json = "{\n   " . join(",\n   ", map {
        $encoder->indent( $_ ne 'tags');
        my $v = $encoder->encode($idx_meta->{$_});
        chomp $v;
        $v =~ s/^(?![[{])/   /gm if ref $idx_meta->{$_} && $_ ne 'tags';
        qq{"$_": $v}
    } grep {
        defined $idx_meta->{$_}
    } qw(
        name abstract description version date maintainer release_status user
        sha1 license prereqs provides tags resources generated_by no_index
        meta-spec
    )) . "\n}\n";

    # Return the distribution metadata.
    my $p = $idx_meta->{provides};
    return {
        name        => $idx_meta->{name},
        version     => $idx_meta->{version},
        relstatus   => $idx_meta->{release_status},
        abstract    => $idx_meta->{abstract},
        description => $idx_meta->{description},
        json        => $json,
        tags        => encode_array_literal( $idx_meta->{tags} || []),
        provided    => encode_array_literal([
            map { [ $_ => $p->{$_}{version}, $p->{$_}{abstract} // '' ] } sort keys %{ $p }
        ]),
    };
$$;

-- Disallow end-user from using this function.
REVOKE ALL ON FUNCTION setup_meta(LABEL, TEXT, TEXT) FROM PUBLIC;

CREATE OR REPLACE FUNCTION record_ownership(
    nick  LABEL,
    exts  TEXT[]
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE
    owned    CITEXT[];
    is_owner BOOLEAN;
BEGIN
    -- See what we own already.
    SELECT array_agg(e.name::text), bool_and(e.owner = nick OR co.nickname IS NOT NULL)
      INTO owned, is_owner
      FROM extensions e
      LEFT JOIN coowners co ON e.name = co.extension AND co.nickname = nick
     WHERE e.name = ANY(exts);

    -- If nick is not owner or cowowner of any extension, return false.
    IF NOT is_owner THEN RETURN FALSE; END IF;

    IF owned IS NULL OR array_length(owned, 1) <> array_length(exts, 1) THEN
        -- There are some other extensions. Make nick the owner.
        INSERT INTO extensions (name, owner)
        SELECT e, nick
          FROM unnest(exts) AS e
         WHERE e <> ALL(COALESCE(owned, '{}'));
    END IF;

    -- Good to go.
    RETURN TRUE;
END;
$$;

-- Disallow end-user from using this function.
REVOKE ALL ON FUNCTION record_ownership(LABEL, TEXT[]) FROM PUBLIC;

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
    distmeta record;
BEGIN
    distmeta  := setup_meta(nick, sha1, meta);
    -- Check permissions for provided extensions.
    IF NOT record_ownership(nick, ARRAY(
        SELECT distmeta.provided[i][1] FROM generate_subscripts(distmeta.provided, 1) AS i
    )) THEN
        RAISE EXCEPTION 'User “%” does not own all provided extensions', nick;
    END IF;

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

CREATE OR REPLACE FUNCTION get_distribution(
    dist    TERM,
    version SEMVER
) RETURNS TABLE (
    template TEXT,
    subject  TEXT,
    json     TEXT
) LANGUAGE plpgsql STRICT STABLE SECURITY DEFINER AS $$
/*

Returns all of the metadata updates to be stored for a given distribution. The
output is the same as for `add_distribution()`, but the distribution must
already exist in the database. Useful for reindexing a distribution or
re-generating metadata files. If the distribution or its version do not exist,
no rows will be returned.

*/
DECLARE
    distmeta TEXT;
    nick     LABEL;
BEGIN
    SELECT creator, meta INTO nick, distmeta
      FROM distributions
     WHERE distributions.name    = dist
       AND distributions.version = get_distribution.version;
    IF nick IS NOT NULL THEN RETURN QUERY
              SELECT 'meta'::TEXT, LOWER(dist), distmeta
        UNION SELECT 'dist',       LOWER(dist), dist_json(dist)
        UNION SELECT 'extension',  * FROM extension_json(dist, version)
        UNION SELECT 'user',       LOWER(nick::TEXT), user_json(nick)
        UNION SELECT 'tag',        * FROM tag_json(dist, version)
        UNION SELECT 'stats',      * FROM all_stats_json();
    END IF;
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
useful of the format of the generated `META.json` file changes: just call this
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

