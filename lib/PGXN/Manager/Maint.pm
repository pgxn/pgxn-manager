package PGXN::Manager::Maint;

use 5.10.0;
use utf8;
use Moose;
use File::Spec;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname basename);
use Encode qw(encode_utf8);
use Carp;
use namespace::autoclean;

our $VERSION = v0.16.1;

has verbosity => (is => 'rw', required => 1, isa => 'Int', default => 0);
has exitval   => (is => 'rw', required => 0, isa => 'Int', default => 0);
has workdir   => (is => 'rw', required => 0, isa => 'Str', lazy => 1, default => sub {
    require PGXN::Manager;
    my $tmpdir = PGXN::Manager->new->config->{tmpdir}
        || File::Spec->catdir(File::Spec->tmpdir, 'pgxn');
    make_path $tmpdir if !-d $tmpdir;
    File::Spec->catdir($tmpdir, "working.$$");
});

sub go {
    my $class = shift;
    $class->new( $class->_config )->run(@ARGV)->exitval;
}

sub run {
    my ($self, $command) = (shift, shift);
    $command =~ s/-/_/g;
    my $meth = $self->can($command)
        or croak qq{PGXN Maint: "$command" is not a command};
    require PGXN::Manager;
    $self->$meth(@_);
}

sub update_stats {
    my $self = shift;
    my $pgxn = PGXN::Manager->instance;
    my $tmpl = $pgxn->uri_templates->{stats};
    my $dir  = File::Spec->catdir($self->workdir, 'dest');
    my $root = PGXN::Manager->instance->config->{mirror_root};
    my %files;
    make_path $dir;

    $pgxn->conn->run(sub {
        my $sth = $_->prepare('SELECT * FROM all_stats_json()');
        $sth->execute;
        $sth->bind_columns(\my ($stat_name, $json));

        while ($sth->fetch) {
            my $uri = $tmpl->process( stats => $stat_name );
            my $fn  = File::Spec->catfile($dir, $uri->path_segments);
            $self->_write_json_to($json, $fn);
            $files{$fn} = File::Spec->catfile($root, $uri->path_segments);
        }
    });

    # Move all the other files over.
    while (my ($src, $dest) = each %files) {
        PGXN::Manager->move_file($src, $dest);
    }

    return $self;
}

sub update_users {
    my $self = shift;
    my $pgxn = PGXN::Manager->instance;
    my $tmpl = $pgxn->uri_templates->{user};
    my $dir  = File::Spec->catdir($self->workdir, 'dest');
    my $root = PGXN::Manager->instance->config->{mirror_root};
    make_path $dir;

    $pgxn->conn->run(sub {
        my $sth = $_->prepare(q{
            SELECT LOWER(nickname), user_json(nickname)
              FROM users
             ORDER BY nickname
        });
        $sth->execute;
        $sth->bind_columns(\my ($nick, $json));

        while ($sth->fetch) {
            my $uri = $tmpl->process( user => $nick );
            my $fn  = File::Spec->catfile($dir, $uri->path_segments);
            $self->_write_json_to($json, $fn);
            PGXN::Manager->move_file(
                $fn,
                File::Spec->catfile($root, $uri->path_segments)
            );
        }
    });

    return $self;
}

sub _handle_error {
    my $self = shift;
    my $l = PGXN::Manager::Locale->get_handle;
    my $err = $l->maketext(@_);
    $err =~ s{<br />}{}g;
    warn encode_utf8 $err, "\n";
    $self->exitval( $self->exitval + 1 );
}

sub reindex {
    my ($self, @args) = @_;
    my $pgxn = PGXN::Manager->instance;
    my $tmpl = $pgxn->uri_templates->{download};
    my $root = PGXN::Manager->instance->config->{mirror_root};

    require PGXN::Manager::Distribution;

    $pgxn->conn->run(sub {
        my $dbh = shift;
        my $sth = $dbh->prepare(
            'SELECT creator FROM distributions WHERE name = ? AND version = ?'
        );
        while (@args) {
            my ($dist, $fn, $name, $version);
            if (-e $args[0]) {
                # It's likely a file name. Parse for dist name and version.
                $fn = shift @args;
                $dist = PGXN::Manager::Distribution->new(
                    archive  => $fn,
                    basename => basename($fn),
                    creator  => '',
                );
                unless ($dist->extract_meta) {
                    $self->_handle_error($dist->error);
                    next;
                }

                my $meta = $dist->distmeta;
                $name    = $meta->{name};
                $version = $meta->{version};
            } else {
                # Mostly likely name and version.
                ($name, $version) = (lc shift @args, lc shift @args);
                my $uri = $tmpl->process( dist => $name, version => $version );
                $fn = File::Spec->catfile($root, $uri->path_segments);
                $dist = PGXN::Manager::Distribution->new(
                    archive  => $fn,
                    basename => basename($fn),
                    creator  => '',
                );
            }

            # Find the user who uploaded it.
            my ($user) = $dbh->selectrow_array($sth, undef, $name, $version);
            unless ($user) {
                $self->_handle_error(
                    '“[_1] [_2]” is not a known release',
                    $name, $version
                );
                next;
            }

            # Do the work.
            $dist->creator($user);
            unless ($dist->reindex) {
                $self->_handle_error($dist->error);
            }
        }
    });
    return $self;
}

sub reindex_all {
    my ($self, @args) = @_;
    my $pgxn = PGXN::Manager->instance;
    my $tmpl = $pgxn->uri_templates->{download};
    my $root = PGXN::Manager->instance->config->{mirror_root};

    require PGXN::Manager::Distribution;

    $pgxn->conn->run(sub {
        my $sth = shift->prepare(
            'SELECT LOWER(name), LOWER(version::TEXT), creator FROM distributions'
            . (@args ? ' WHERE name = ANY(?)' : '')
            . ' ORDER BY name, version DESC'
        );
        $sth->execute(@args ? \@args : ());
        $sth->bind_columns(\my ($name, $version, $user));
        while ($sth->fetch) {
            my $uri = $tmpl->process( dist => $name, version => $version );
            my $fn  = File::Spec->catfile($root, $uri->path_segments);
            my $dist = PGXN::Manager::Distribution->new(
                archive  => $fn,
                basename => basename($fn),
                creator  => $user,
            );
            unless ($dist->reindex) {
                $self->_handle_error($dist->error);
            }
        }
    });
    return $self;
}

sub _write_json_to {
    my ($self, $json, $fn) = @_;
    make_path dirname $fn;
    open my $fh, '>encoding(UTF-8)', $fn or die "Cannot open $fn: $!\n";
    print $fh $json;
    close $fh or die "Cannot close $fn: $!\n";
}

sub DEMOLISH {
    my $self = shift;
    if (my $path = $self->workdir) {
        remove_tree $path if -e $path;
    }
}

sub _pod2usage {
    shift;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
        '-input'    => __FILE__,
        @_
    );
}

sub _config {
    my $self = shift;
    require Getopt::Long;
    Getopt::Long::Configure( qw(bundling) );

    my %opts = (
        verbosity => 0,
    );

    Getopt::Long::GetOptions(
        'env|E=s'    => \my $env,
        'verbose|V+' => \$opts{verbosity},
        'help|h'     => \$opts{help},
        'man|M'      => \$opts{man},
        'version|v'  => \$opts{version},
    ) or $self->_pod2usage;
    $ENV{PLACK_ENV} = $env || 'development';

    # Handle documentation requests.
    $self->_pod2usage(
        ( $opts{man} ? ( '-sections' => '.+' ) : ()),
        '-exitval' => 0,
    ) if $opts{help} or $opts{man};

    # Handle version request.
    if ($opts{version}) {
        require File::Basename;
        require version;
        no strict 'refs';
        print File::Basename::basename($0), ' (', __PACKAGE__, ') ',
            sprintf('v%vd', $VERSION), $/;
        exit;
    }

    return %opts;
}

1;
__END__

=head1 Name

PGXN::Manager::Maint - PGXN Manager maintenance utility

=head1 Synopsis

  use PGXN::Manager::Maint;
  PGXN::Manager::Maint->go;

=head1 Description

This module provides the implementation for for C<pgxn_maint>, though it may
of course be used programmatically as a library. To use it, simply instantiate
it and call one of its maintenance methods. Or use it from L<pgxn_maint> on
the command-line for easy maintenance of your database and mirror.

Periodically, things come up where you need to do a maintenance task. Perhaps
a new version of PGXN::Manager provides new JSON keys in a stats file, or adds
new metadata to a distribution F<META.json> file. Use PGXN::Manager::Maint to
regenerate the needed files, or to reindex existing distributions so that
their metadata will be updated.

=head1 Class Interface

=head2 Constructor

=head3 C<new>

  my $maint = PGXN::Manager::Maint->new(%params);

Creates and returns a new PGXN::Manager::Maint object. The supported parameters
are:

=over

=item C<verbosity>

An incremental integer specifying the level of verbosity to use during a sync.
By default, PGXN::Manager::Maint runs in quiet mode, where only errors are emitted
to C<STDERR>.

=back

=head2 Class Method

=head3 C<go>

  PGXN::Manager::Maint->go;

Called by L<pgxn_maint>. It simply parses C<@ARGV> for options and passes
those appropriate to C<new>. It then calls C<run()> and passes the remaining
values in C<@ARGV>. It thus makes the L<pgxn_maint> interface possible.

=head1 Instance Interface

=head2 Instance Methods

=head3 C<run>

  $maint->run($task, @args);

Runs a maintenance task. Pass in any additional arguments required of the
task. Useful if you don't know in advance what the task will be; otherwise you
could just call the appropriate task method directly.

=head3 C<update_stats>

  $maint->update_stats;

Updates all the system-wide stats files from the database. The stats files are
JSON and their location is defined by the C<stats> URI template in the PGXN
Manager configuration file. Currently, they include:

=over

=item F<dist.json>

=item F<extension.json>

=item F<user.json>

=item F<tag.json>

=item F<summary.json>

=back

=head3 C<update_users>

  $maint->update_users;

Updates the JSON files for all users in the database. The location of the
files is defined by the C<users> URI template in the PGXN Manager
configuration file.

=head3 C<reindex>

  $maint->reindex(@dists_and_versions)
  $maint->reindex(@archives)

Reindexes one or more releases of distributions. Pass in distribution name and
version pairs or paths to archives. Most useful if you need to reindex a
specific version of a distribution or three, like so:

  $maint->reindex(pair => '0.1.1', pair => '0.1.2', '/tmp/pgTAP-0.25.0.zip');

If you need to reindex all versions of a given distribution, or all
distributions (yikes!), use C<reindex_all>, instead.

=head3 C<reindex_all>

  $maint->reindex_all(@dist_names);
  $maint->reindex_all;

Reindexes all releases of the named distributions. If called with no
arguments, it reindexes every distribution in the system. That's not to be
undertaken lightly if you have a lot of distributions. If you need to update
only a few, pass their names. If you need to reindex only specific versions of
a distribution, use C<reindex> instead.

=head2 Instance Accessors

=head3 C<verbosity>

  my $verbosity = $maint->verbosity;
  $maint->verbosity($verbosity);

Get or set an incremental verbosity. The higher the integer specified, the
more verbosity the sync.

=head1 Author

David E. Wheeler <david.wheeler@pgexperts.com>

=head1 Copyright and License

Copyright (c) 2011 David E. Wheeler.

This module is free software; you can redistribute it and/or modify it under
the L<PostgreSQL License|https://www.opensource.org/licenses/postgresql>.

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose, without fee, and without a written agreement is
hereby granted, provided that the above copyright notice and this paragraph
and the following two paragraphs appear in all copies.

In no event shall David E. Wheeler be liable to any party for direct,
indirect, special, incidental, or consequential damages, including lost
profits, arising out of the use of this software and its documentation, even
if David E. Wheeler has been advised of the possibility of such damage.

David E. Wheeler specifically disclaims any warranties, including, but not
limited to, the implied warranties of merchantability and fitness for a
particular purpose. The software provided hereunder is on an "as is" basis,
and David E. Wheeler has no obligations to provide maintenance, support,
updates, enhancements, or modifications.

=cut
