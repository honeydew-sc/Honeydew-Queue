package Honeydew::Queue::JobRunner::Ios;

# ABSTRACT: Choose the correct Resque for iOS jobs
use Moo::Role;

requires 'log';

sub is_real_ios {
    my ($self, $cmd) = @_;
    my $IOS_DEVICE_NAME = 'iOS Mobile Safari';

    return $cmd =~ /-browser=.*$IOS_DEVICE_NAME/i;
}

sub choose_ios_queue {
    my ($self, $cmd) = @_;

    my $local = $self->parse_local_addr($cmd);
    my $queue = 'ios_' . $local;

    return $queue;
}

sub parse_local_addr {
    my ($self, $cmd) = @_;

    my ($local) = $cmd =~ m/-local=((?:\d{1,3}.?){4})/;

    # We _need_ a local address to run real iOS device jobs, and don't
    # really have a clue what to do otherwise.
    if (! $local) {
        my $error = "ERROR: attempting to run iOS job without local ($cmd)";
        $self->log($error);
        die $error;
    }

    return $local;
}

1;
