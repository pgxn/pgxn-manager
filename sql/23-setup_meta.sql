-- sql/23-setup_meta.sql SQL Migration

CREATE OR REPLACE FUNCTION setup_meta(
    IN  nick        LABEL,
    IN  sha1        TEXT,
    IN  "json"      TEXT,
    OUT name        TERM,
    OUT version     SEMVER,
    OUT relstatus   RELSTATUS,
    OUT abstract    TEXT,
    OUT description TEXT,
    OUT provided    TEXT[][],
    OUT tags        CITEXT[],
    OUT "json"      TEXT
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
        ($meta->{resources} ? (values %{ $meta->{resources} }, $meta->{resources}) : ()),
        map { values %{ $_ }} values %{ $meta->{provides} },
        values %{ $meta->{provides} },
        $meta->{provides},
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
