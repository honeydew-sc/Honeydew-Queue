package Honeydew::Queue::JobRunner::Ios;

# ABSTRACT: Choose the correct Resque for iOS jobs
use Moo::Role;

sub is_real_ios {
    my ($cmd) = @_;

    return 0;
}

sub choose_ios_queue {
    my ($cmd) = @_;

}

1;
