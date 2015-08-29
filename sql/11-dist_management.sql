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
    my ($user, $sha1) = (shift, shift);
    my $meta = JSON::XS->new->utf8(0)->decode(shift);

    # Validate the metadata.
    my $pmv = PGXN::Meta::Validator->new($meta);
    elog(ERROR, "Metadata is not valid; errors:\n" . join("\n", $pmv->errors))
        unless $pmv->is_valid;

    # Remove extra fields.
    delete $meta->{'meta-spec'};
    delete $meta->{generated_by};
    delete $meta->{$_} for grep { /^x_/i } keys %{ $meta };
    for my $map (grep { ref $_ eq 'HASH' }
        $meta->{no_index},
        ($meta->{resources} ? ($meta->{resources}, values %{ $meta->{resources} }) : ()),
        $meta->{provides},
        values %{ $meta->{provides} },
        map { values %{ $_ }} values %{ $meta->{provides} },
    ) {
        delete $map->{$_} for grep { /^x_/i } keys %{ $map };
    }

    # Set default release status and add user and sha1.
    $meta->{release_status} ||= 'stable';
    $meta->{user} = $user;
    $meta->{sha1} = $sha1;

    # Set the date; use an existing one if it is available.
    $meta->{date} = spi_exec_query(sprintf
        q{SELECT utc_date(COALESCE(
            (SELECT created_at FROM distributions WHERE name = %s AND version = %s),
            NOW()
        ))},
        quote_literal($meta->{name}),
        quote_literal($meta->{version})
    )->{rows}[0]{utc_date};

    # Recreate the JSON.
    my $encoder = JSON::XS->new->utf8(0)->space_after->allow_nonref->indent->canonical;
    my $json = "{\n   " . join(",\n   ", map {
        $encoder->indent( $_ ne 'tags');
        my $v = $encoder->encode($meta->{$_});
        chomp $v;
        $v =~ s/^(?![[{])/   /gm if ref $meta->{$_} && $_ ne 'tags';
        qq{"$_": $v}
    } grep {
        defined $meta->{$_}
    } qw(
        name abstract description version date maintainer release_status user
        sha1 license prereqs provides tags resources generated_by no_index
        meta-spec
    )) . "\n}\n";

    # Return the distribution metadata.
    my $p = $meta->{provides};
    return {
        name        => $meta->{name},
        version     => $meta->{version},
        relstatus   => $meta->{release_status},
        abstract    => $meta->{abstract},
        description => $meta->{description},
        json        => $json,
        tags        => encode_array_literal( $meta->{tags} || []),
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
-- Moved to 14-add_distribution2.sql.
BEGIN
    RETURN;
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

