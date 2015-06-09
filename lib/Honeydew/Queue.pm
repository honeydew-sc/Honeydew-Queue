package Honeydew::Queue;

# ABSTRACT: Manage Honeydew's nightly queue functionality

use strict;
use warnings;
use Honeydew::Config;
use Moo;
use Resque;

=for markdown [![Build Status](https://travis-ci.org/honeydew-sc/Honeydew-Queue.svg?branch=master)](https://travis-ci.org/honeydew-sc/Honeydew-Queue)

=head1 SYNOPSIS

    use DDP;
    my $hq = Honeydew::Queue->new;
    p $hq->get_queues;

    $hq->drop_nightly_queues;

=head1 DESCRIPTION

This module is a thin wrapper around L<Resque> that implements
Honeydew-specific queue functionality that we'd like.

=attr resque

Optional: By default, we'll instantiate a Resque client for the one
specified by L<Honeydew::Config>; you can also pass in a L<Resque>
object of your choosing if you'd like to mock tests, or use your own
Resque without specifying a config file. See the tests for how to do
that - in particular, the C<before each> section of
C<Honeydew-Queue.t>.

=cut

has resque => (
    is => 'lazy',
    handles => [ qw/push/ ],
    builder => sub {
        my ($self) = @_;

        my ($server, $port) = (
            $self->config->{redis}->{redis_server},
            $self->config->{redis}->{redis_port}
        );

        return Resque->new( redis => $server . ':' . $port );
    }
);

=attr config

We expects an instance of L<Honeydew::Config>; you can inject your own
with the proper settings, but you're probably better served just
giving us a resque object above.

=cut

has config => (
    is => 'lazy',
    default => sub { return Honeydew::Config->instance; }
);

=method get_queues ()

Accepts no args; returns a hashref. The keys are the names of the
queues, and the values are the size of each queue.

=cut

sub get_queues {
    my ($self) = @_;

    my $queues = $self->resque->queues;

    my %queue_jobs = map {
        $_ => $self->resque->size($_)
    } @$queues;

    return \%queue_jobs;
}

=method drop_nightly_queues ()

Accepts no args; returns this object for lack of anything better to
do. There's no error handling in place. We'll look up the nightly
queues from the C<local> entry in our L<Honeydew::Config>, and drop
only the nightly ones. This is useful for resetting your queue to a
clean state before starting a new batch of tests.

=cut

sub drop_nightly_queues {
    my ($self) = @_;

    my $nightly_queues = $self->_nightly_queues;

    foreach ($self->_nightly_queues) {
        $self->resque->remove_queue($_);
    }

    return $self;
}

sub _nightly_queues {
    my ($self) = @_;

    my $nightlies = $self->config->{local};

    return keys %$nightlies;
}

1;
