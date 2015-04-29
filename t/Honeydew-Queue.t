use strict;
use warnings;
use Test::Spec;
use Test::Deep;
use Redis;
use Resque;
use Test::RedisServer;

BEGIN: {
    unless (use_ok('Honeydew::Queue')) {
        BAIL_OUT("Couldn't load Honeydew::Queue");
        exit;
    }
}

my $redis_server;
eval {
    $redis_server = Test::RedisServer->new;
} or plan skip_all => 'redis-server is required to this test';

my $redis = Redis->new( $redis_server->connect_info );

describe 'Honeydew queue' => sub {
    my ($hq);

    before each => sub {
        $hq = Honeydew::Queue->new(
            resque => Resque->new( redis => $redis )
        );
    };

    after each => sub {
        reset_resque($hq);
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
        seed_test_queues($hq, qw/ jenn_cs
                                  carl_gp
                                  pablo_qa
                                  imac_52
                                  jenn2_c5
                                  screenshots
                                  dont_drop_me /
                     );

        $hq->drop_nightly_queues;
        cmp_deeply( $hq->get_queues, {
            screenshots => 1,
            dont_drop_me => 1
        });
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
