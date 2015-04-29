package Honeydew::Queue;

# ABSTRACT: Manage Honeydew's nightly queue functionality

use strict;
use warnings;
use Honeydew::Config;
use Moo;
use Resque;

=for markdown [![Build Status](https://travis-ci.org/honeydew-sc/Honeydew-Queue.svg?branch=master)](https://travis-ci.org/honeydew-sc/Honeydew-Queue)

=head1 SYNOPSIS

=head1 DESCRIPTION

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

has config => (
    is => 'lazy',
    default => sub { return Honeydew::Config->instance; }
);

sub get_queues {
    my ($self) = @_;

    my $queues = $self->resque->queues;

    my %queue_jobs = map {
        $_ => $self->resque->size($_)
    } @$queues;

    return \%queue_jobs;
}

sub drop_nightly_queues {
    my ($self) = @_;

    my $nightly_queues = $self->_nightly_queues;

    foreach ($self->_nightly_queues) {
        $self->resque->remove_queue($_);
    }
}

sub _nightly_queues {
    my ($self) = @_;

    my $nightlies = $self->config->{local};

    return keys %$nightlies;
}

1;
