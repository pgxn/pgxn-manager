-- sql/1282692433-add_distribution.sql SQL Migration

CREATE OR REPLACE FUNCTION setup_meta(
    IN  nick        LABEL,
    IN  sha1        TEXT,
    IN  json        TEXT,
    OUT name        CITEXT,
    OUT VERSION     SEMVER,
    OUT relstatus   RELSTATUS,
    OUT abstract    TEXT,
    OUT description TEXT,
    OUT provided    TEXT[][],
    OUT json        TEXT
) LANGUAGE plperl IMMUTABLE AS $$
    my $idx_meta  = { owner => shift, sha1 => shift };
    my $dist_meta = JSON::XS::decode_json shift;

    # Check required keys.
    for my $key qw(name version license maintainer abstract) {
        $idx_meta->{$key} = $dist_meta->{$key} or elog(
            ERROR, qq{Metadata is missing the required "$key" key}
        );
    }

    # Grab optional fields.
    for my $key qw(description tags no_index prereqs provides release_status resources) {
        $idx_meta->{$key} = $dist_meta->{$key} if exists $dist_meta->{$key};
    }

    # Set default release status.
    $idx_meta->{release_status} ||= 'stable';

    # Normalize version string.
    my $semverify = sub { spi_exec_query(
        sprintf 'SELECT clean_semver(%s)', quote_nullable(shift)
    )->{rows}[0]{clean_semver} };
    $idx_meta->{version} = $semverify->($idx_meta->{version});

    # Normalize "prereq" version strings.
    if (my $prereqs = $idx_meta->{prereqs}) {
        for my $phase (values %{ $prereqs }) {
            for my $type ( values %{ $phase }) {
                for my $prereq (keys %{ $type }) {
                    $type->{$prereq} = $semverify->($type->{$prereq});
                }
            }
        }
    }

    if (my $provides = $idx_meta->{provides}) {
        # Normalize "provides" version strings.
        for my $ext (values %{ $provides }) {
            $ext->{version} = $semverify->($ext->{version});
        }
    } else {
        # Default to using the distribution name as the extension.
        $idx_meta->{provides} = {
            $idx_meta->{name} => { version => $idx_meta->{version} }
        };
    }

    # Recreate the JSON.
    my $encoder = JSON::XS->new->space_after->allow_nonref->indent->canonical;
    my $json = "{\n   " . join(",\n   ", map {
        $encoder->indent( $_ ne 'tags');
        my $v = $encoder->encode($idx_meta->{$_});
        chomp $v;
        $v =~ s/^(?![[{])/   /gm if ref $idx_meta->{$_} && $_ ne 'tags';
        qq{"$_": $v}
    } grep {
        defined $idx_meta->{$_}
    } qw(
        name abstract description version maintainer release_status owner sha1
        license prereqs provides tags resources generated_by no_index
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
        provided    => encode_array_literal([
            map { [ $_ => $p->{$_}{version} ] } sort keys %{ $p }
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
    SELECT array_agg(e.name), bool_and(e.owner = nick OR co.nickname IS NOT NULL)
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
) RETURNS TEXT LANGUAGE plpgsql STRICT SECURITY DEFINER AS $$
/*

    % SELECT add_distribution('theory', 'ebf381e2e1e5767fb068d1c4423a9d9f122c2dc6', '{
        "name": "pair",
        "version": "0.0.01",
        "license": "postgresql",
        "maintainer": "theory",
        "abstract": "Ordered pair",
        "provides": {
            "pair": { "file": "pair.sql.in", "version": "0.02.02" },
            "trip": { "file": "trip.sql.in", "version": "0.02.01" }
        },
        "release_status": "testing"
    }');
                           add_distribution                                                                                                                                                   
    ─────────────────────────────────────────────────────────────
     {
       "maintainer": "theory",
       "owner": "theory",
       "sha1": "ebf381e2e1e5767fb068d1c4423a9d9f122c2dc6",
       "version": "0.0.1",
       "name": "pair",
       "license": "postgresql",
       "provides": {
         "pair": { "version": "0.2.2", "file": "pair.sql.in" },
         "trip": { "version": "0.2.1", "file": "trip.sql.in" }
       },
       "abstract": "Ordered pair",
       "release_status": "testing"
     }

Creates a new distribution, returning the JSON to be used in the metadata file
for the distribution. The nickname of the uploading user (owner) must be
passed as the first argument. The SHA1 of the distribution file must be passed
as the second argument. All other metadata is parsed from the JSON string,
which should contain the complete contents of the distribution's `META.json`
file. The required keys in the JSON metadata are:

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

See the [PGXN Meta Spec](http://github.com/theory/pgxn/wiki/PGXN-Meta-Spec)
for the complete list of specified keys.

With this data, `add_distribution()` does the following things:

* Parses the JSON string and validates that all required keys are present.
  Throws an exception if they're not.

* Creates a new metadata structure and stores all the required and many of hte
  optional meta spec keys, as well as the SHA1 of the distribution file and
  the owner's nickname.

* Normalizes all of the version numbers found in the metadata into compliant
  semantic version strings. See `clean_semver()` for details on how
  non-compliant version strings are converted.

* Specifies that the provided extension is the same as the distribution name
  and version if no "provides" metadata is present in the distribution
  metadata.

* Validates that the uploading user is owner or co-owner of all provided
  extensions. If no one is listed as owner of one or more included extensions,
  the user will be assigned ownership. If the user is not owner or co-owner of
  any included extensions, an exception will be thrown.

* Inserts the distribution data into the `distributions` table.

* Inserts records for all included exentions into the
  `distribution_extensions` table.

* Returns the index metadata as a JSON string. If any argument is `NULL`,
  returns `NULL`, in which case the distribution will not have been added.

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
        INSERT INTO distributions (name, version, relstatus, abstract, description, sha1, owner, meta)
        VALUES (distmeta.name, distmeta.version, COALESCE(distmeta.relstatus, 'stable'),
                distmeta.abstract, COALESCE(distmeta.description, ''), sha1, nick, distmeta.json);
    EXCEPTION WHEN unique_violation THEN
       RAISE EXCEPTION 'Distribution % % already exists', distmeta.name, distmeta.version;
    END;

    -- Record the extensions in this distribution.
    BEGIN
        INSERT INTO distribution_extensions (extension, ext_version, distribution, dist_version)
        SELECT distmeta.provided[i][1], distmeta.provided[i][2], distmeta.name, distmeta.version
          FROM generate_subscripts(distmeta.provided, 1) AS i;
    EXCEPTION WHEN unique_violation THEN
       IF array_length(distmeta.provided, 1) = 1 THEN
           RAISE EXCEPTION 'Extension % version % already exists',
               distmeta.provided[1][1], distmeta.provided[1][2];
       ELSE
           distmeta.provided := ARRAY(
               SELECT distmeta.provided[i][1] || ' ' || distmeta.provided[i][2]
                 FROM generate_subscripts(distmeta.provided, 1) AS i
           );
           RAISE EXCEPTION 'One or more versions of the provided extensions already exist:
  %', array_to_string(distmeta.provided, '
  ');
       END IF;
    END;

    RETURN distmeta.json;
END;
$$;
