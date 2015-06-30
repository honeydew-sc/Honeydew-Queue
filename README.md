# NAME

Honeydew::Queue - Manage Honeydew's nightly queue functionality

[![Build Status](https://travis-ci.org/honeydew-sc/Honeydew-Queue.svg?branch=master)](https://travis-ci.org/honeydew-sc/Honeydew-Queue)

# VERSION

version 0.07

# SYNOPSIS

    use DDP;
    my $hq = Honeydew::Queue->new;
    p $hq->get_queues;

    $hq->drop_nightly_queues;

# DESCRIPTION

This module is a thin wrapper around [Resque](https://metacpan.org/pod/Resque) that implements
Honeydew-specific queue functionality that we'd like.

# ATTRIBUTES

## resque

Optional: By default, we'll instantiate a Resque client for the one
specified by [Honeydew::Config](https://metacpan.org/pod/Honeydew::Config); you can also pass in a [Resque](https://metacpan.org/pod/Resque)
object of your choosing if you'd like to mock tests, or use your own
Resque without specifying a config file. See the tests for how to do
that - in particular, the `before each` section of
`Honeydew-Queue.t`.

## config

We expects an instance of [Honeydew::Config](https://metacpan.org/pod/Honeydew::Config); you can inject your own
with the proper settings, but you're probably better served just
giving us a resque object above.

# METHODS

## get\_queues ()

Accepts no args; returns a hashref. The keys are the names of the
queues, and the values are the size of each queue.

## drop\_nightly\_queues ()

Accepts no args; returns this object for lack of anything better to
do. There's no error handling in place. We'll look up the nightly
queues from the `local` entry in our [Honeydew::Config](https://metacpan.org/pod/Honeydew::Config), and drop
only the nightly ones. This is useful for resetting your queue to a
clean state before starting a new batch of tests.

# BUGS

Please report any bugs or feature requests on the bugtracker website
https://github.com/honeydew-sc/Honeydew-Queue/issues

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

# AUTHOR

Daniel Gempesaw <gempesaw@gmail.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Daniel Gempesaw.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
