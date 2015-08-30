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
