use strict;
use warnings;
use Honeydew::Queue;
use Redis;
use Resque;
use Test::Spec;
use Test::RedisServer;

my $redis_server;
eval {
    $redis_server = Test::RedisServer->new;
} or plan skip_all => 'redis-server is required to this test';

my $redis = Redis->new( $redis_server->connect_info );

describe 'Honeydew queue' => sub {
    my ($hq);

    before each => sub {
        $hq = Honeydew::Queue->new(
            resque => Resque->new( redis => $redis ),
            config => {
                local => {
                    nightly_queue => 1,
                    other_nightly_queue => 1,
                }
            }
        );
    };

    it 'should tell us about the queues' => sub {
        seed_test_queues($hq, 'queue1', 'queue2');
        my $job_queues = $hq->get_queues;

        cmp_deeply( $job_queues, {
            queue1 => 1,
            queue2 => 1
        });

    };

    it 'should drop nightly queues' => sub {
        seed_test_queues($hq, qw/ nightly_queue
                                  other_nightly_queue
                                  not_nightly
                                  dont_drop_me /
                     );

        $hq->drop_nightly_queues;
        cmp_deeply( $hq->get_queues, {
            not_nightly => 1,
            dont_drop_me => 1
        });
    };

    after each => sub {
        reset_resque($hq);
    };
};

sub seed_test_queues {
    my ($hq, @queues) = @_;

    foreach (@queues) {
        $hq->push(
            $_ => {
                class => 'Test::HQ::Job',
                args => []
            }
        );
    }
}

sub reset_resque {
    my ($hq) = @_;

    $hq->resque->flush_namespace;
}

runtests;
