package PGXN::Manager::Consumer;

use 5.10.0;
use strict;
use warnings;
use utf8;
use Moose;
use JSON::XS;
use Try::Tiny;
use Encode qw(encode_utf8);
use Carp;
use Time::HiRes qw(sleep);
use PGXN::Manager;
use Proc::Daemon;
use IO::File;
use POSIX ();
use Fcntl qw(:flock);
use Cwd;
use namespace::autoclean;

our $VERSION = v0.30.1;
use constant CHANNELS => qw(release new_user new_mirror);

has verbose  => (is => 'ro', isa => 'Int', required => 1, default => 0);
has interval => (is => 'ro', isa => 'Num', required => 1, default => 5);
has continue => (is => 'rw', isa => 'Bool', required => 1, default => 1);
has log_fh   => (is => 'ro', isa => 'IO::Handle', required => 1, default => sub {
    _log_fh()
});
has conn     => (is => 'ro', isa => 'DBIx::Connector', lazy => 1, default => sub {
    # Use our own connetion instead of $pgxn->conn in order to add the callback.
    my $self = shift;
    my $cb = $self->verbose ? sub {
        $_[0]->do("LISTEN pgxn_$_") for CHANNELS;
        $self->log("INFO: Listening on ", join ', ', map { s/^pgxn_//r } @{
            $_[0]->selectcol_arrayref('SELECT * FROM pg_listening_channels()')
        });
        return;
    } : sub {
        $_[0]->do("LISTEN pgxn_$_") for CHANNELS;
        return;
    };
    # Once connected or reconnected, listen for NOTIFY messages.
    PGXN::Manager->instance->_connect( Callbacks => { connected => $cb } );
});

sub _log_fh {
    my $fn = shift;
    my $fh = $fn ? IO::File->new($fn, '>>:utf8')
                 : IO::Handle->new_from_fd(fileno STDOUT, 'w');
    binmode $fh, ":utf8";
    $fh->autoflush(1);
    $fh;
}

sub go {
    my $class = shift;
    my $cfg = $class->_config;

    if (delete $cfg->{daemonize}) {
        my $daemon = Proc::Daemon->new(
            work_dir     => getcwd,
            dont_close_fh => [qw(STDERR STDOUT)],
            pid_file     => $cfg->{pid},
        );
        if (my $pid = $daemon->Init) {
            _log(_log_fh($cfg->{'log-file'}), "INFO: Forked PID $pid");
            return 0;
        }
    }

    # In the child process. Set up log file handle and go.
    $cfg->{log_fh} = _log_fh delete $cfg->{'log-file'};
    my $cmd = $class->new( $cfg );
    $SIG{TERM} = sub { $cmd->continue(0) };
    $cmd->run(@ARGV);
}

sub run {
    my $self = shift;
    my $pgxn = PGXN::Manager->instance;
    my $cfg = $pgxn->config->{consumers} || do {
        $self->log("WARN: No consumers configured; messages will be dropped");
        undef
    };

    # Load the map from events to consumers.
    my $consumers_for = $self->load_consumers($cfg);

    # Continuously listen for NOTIFY messgages.
    while ($self->continue) {
        $self->consume($consumers_for);
        sleep($self->interval);
    }

    $self->log("INFO: Shutting down");
    return 0;
}

sub load_consumers {
    my ($self, $cfg) = @_;
    my %consumers;
    for my $cfg (@{ $cfg }) {
        my $type = delete $cfg->{type}
            or die "No type specified for event consumer\n";
        my $pkg = __PACKAGE__ . "::$type";
        $self->log("INFO: Loading $pkg") if $self->verbose > 1;
        eval "use $pkg";
        die "Error loading $pkg: $@\n" if $@;
        my $events = delete $cfg->{events};
        my $consumer = $pkg->new(
            verbose => $self->verbose,
            config  => $cfg,
        );

        for my $e (@{ $events }) {
            $self->log("INFO: Configuring $pkg for $e") if $self->verbose > 1;
            push @{ $consumers{$e} ||= [] } => $consumer;
        }
    }

    return \%consumers;
}

sub consume {
    my ($self, $consumers_for) = @_;
    try {
        $self->conn->run(sub {
            # Notify payload treated as UTF-8 text, so already decoded from UTF-8 bytes.
            my $json = JSON::XS->new->utf8(0);
            my $dbh = shift;
            $self->log("INFO: Consuming") if $self->verbose > 2;
            while (my $notify = $dbh->pg_notifies) {
                my ($name, $pid, $msg) = @{ $notify };
                $self->log("INFO: Received “$name” event from PID $pid")
                    if $self->verbose;
                unless ($name =~ s/^pgxn_//) {
                    $self->log("WARN: Unknown channel “$name”; skipping");
                    next;
                }
                my $handlers = $consumers_for->{$name} || do {
                    $self->log(
                        "INFO: No handlers configured for ",
                        "pgxn_$name channel; skipping",
                    )if $self->verbose;
                    next;
                };

                # Decode the JSON payload;
                my $meta = try {
                    $json->decode($msg);
                } catch {
                    $self->log("ERORR: Cannot decode JSON: $_");
                    undef;
                };
                next unless $meta;

                # Run all the handlers.
                for my $h (@{ $handlers }) {
                    $self->log("INFO: Sending to ", $h->name, " handler")
                        if $self->verbose;
                    try { $h->handle($name, $meta) }
                    catch { $self->log("ERROR: $_") };
                }
            }
        });
    } catch {
        $self->log("ERROR: $_");
    };
    return 1;
}

sub log {
    _log(shift->log_fh, @_);
}

sub _log {
    my $fh = shift;
    flock $fh, LOCK_EX;
    say {$fh}  POSIX::strftime('%Y-%m-%dT%H:%M:%SZ - ', gmtime), join '', @_;
    flock $fh, LOCK_UN;
}

sub _config {
    my $self = shift;
    require Getopt::Long;
    Getopt::Long::Configure( qw(bundling) );

    my %opts = (
        verbose  => 0,
        env      => 'development',
        interval  => 5,
    );

    Getopt::Long::GetOptions(
        \%opts,
        'env|E=s',
        'daemonize|D',
        'pid=s',
        'log-file|l=s',
        'interval|i=s',
        'verbose|V+',
        'help|h',
        'man|M',
        'version|v',
    ) or $self->_pod2usage;
    $ENV{PLACK_ENV} = delete $opts{env};

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

    return \%opts;
}

sub _pod2usage {
    shift;
    require Pod::Usage;
    Pod::Usage::pod2usage(
        '-verbose'  => 99,
        '-sections' => '(?i:(Usage|Options))',
        '-exitval'  => 1,
        '-input'    => $0,
        @_
    );
}

1;
__END__

=head1 Name

PGXN::Manager::Consumer - Consume and handle PGXN Manager event notifications

=head1 Synopsis

  use PGXN::Manager::Consumer;
  PGXN::Manager::Consumer->go;

=head1 Description

This module provides the implementation for for C<pgxn_consumer>, to consume
and handle PostgreSQL C<NOTIFY> events sent by PGXN Manager. The current list
of events is:

=over

=item C<release>

Sent when a a new release is uploaded.

=item C<new_user>

Sent when a new user has been approved by an admin.

=item C<new_mirror>

Sent when a new mirror has been added.

=back

=head1 Class Interface

=head2 Constructor

=head3 C<new>

  my $consumer = PGXN::Manager::Consumer->new(%params);

Creates and returns a new PGXN::Manager::Consumer object. The supported
parameters are:

=over

=item C<verbosity>

An incremental integer specifying the level of verbosity to use during a sync.
By default, PGXN::Manager::Consumer runs in quiet mode, where only errors are
emitted.

=item C<interval>

A decimal value specifying how many seconds to sleep between calls to consume
C<NOTIFY> events. Defaults to C<5>, meaning it will pause for 5 seconds after
consuming messages before making the call to consume more.

=item C<log_fh>

An IO::Handle for logging. Defaults to C<STDOUT>.

=back

=head2 Class Method

=head3 C<go>

  PGXN::Manager::Consumer->go;

Called by L<pgxn_consumer>. It simply parses C<@ARGV> for options and
actually run the consumer. When C<--daemonize> is specified, it forks off a
separate process, writing the PID to the location specified by the C<--pid>
option or, if not specified, to C<STDOUT>. It then sets up a termination
signal handler to ensure a graceful shutdown waiting for any in-flight
message processing to complete.

It then calls C<run()>, passing any remaining values from C<@ARGV>, to do the
work.

=head1 Instance Interface

=head2 Instance Methods

=head3 C<run>

  $consumer->run($task, @args);

Calls C<load_consumers> to load all the configured consumers, then runs the
listener, consuming events and passing them off to handlers configure to
handle them. It runs continuously, sleeping C<interval> seconds between each
call to to consume events, until C<continue> is false (set by the
termination signal handler installed by C<go()>).

=head3 C<load_consumers>

  my $consumers_for_event = $consumer->load_consumers($cfg);

Loads all of the consumers present in C<$cfg> and returns a hash reference
mapping channel names to each consumer configured to handle those channel's
events. Throws an exception when a handler class cannot be loaded or an
instance created.

=head3 C<consume>

  $consumer->consume($manager, $consumers);

Called by C<run()>, this method performs a single check for events in all
PGXN C<NOTIFY> channels, dispatching any it consumes to the handlers
configured to handle them, if any.

=head3 C<log>

  $consumer->log("INFO: Hello");

Write a message to the log.

=head2 Instance Accessors

=head3 C<verbosity>

  my $verbosity = $consumer->verbosity;
  $consumer->verbosity($verbosity);

Get or set an incremental verbosity. The higher the integer specified, the
more verbose the sync.

=head3 C<interval>

The number of seconds to sleep between calls to consume messages. Defaults
to 5.

=head3 C<continue>

Boolean telling C<run()> to continue processing. Set to false by the
signal handler installed by C<go> in C<--daemonize> mode, which then causes
the service to gracefully shut down after its next C<interval> consuming
events.

=head3 C<log_fh>

Logging file handle.

=head1 Author

David E. Wheeler <david@justatheory.com>

=head1 Copyright and License

Copyright (c) 2011-2023 David E. Wheeler.

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
