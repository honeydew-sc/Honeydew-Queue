#! /usr/bin/perl

use strict;
use warnings;
use DBD::Mock;
use DBI;
use Test::Spec;

use Honeydew::Config;
use Honeydew::Queue::Nightly;

describe 'Nightly' => sub {
    my ($nightly, $dbh, $config);

    $dbh = DBI->connect( 'DBI:Mock:', '', '' )
      || die "Cannot create handle: $DBI::errstr\n";

    before each => sub {
        $config = Honeydew::Config->instance;
        $config->{honeydew}->{basedir} = File::Spec->catfile( dirname(__FILE__), 'fixture' );

        $nightly = Honeydew::Queue::Nightly->new(
            dbh => $dbh,
            config => $config
        );
    };

    describe 'sets' => sub {

        it 'should query the monitor table for expected sets' => sub {
            mock_expected_sets( $dbh );
            my $expected_sets = $nightly->expected_sets;
            is( $expected_sets->[0], 'fake.set fake host fake browser' );
            is( $expected_sets->[1], 'other_fake.set other fake host other fake browser' );
        };

        it 'should query the setRun table for existing sets' => sub {
            mock_actual_sets( $dbh );
            my $actual_sets = $nightly->actual_sets;
            is_deeply( $actual_sets, { 1 => 'fake.set fake host fake browser' });
        };

        it 'should get a proper list of the sets to be queued' => sub {
            mock_expected_sets( $dbh );
            mock_actual_sets( $dbh );
            my $missing_sets = $nightly->get_sets_to_be_queued;
            is( $missing_sets->[0], 'other_fake.set other fake host other fake browser' );
        };

        describe 'convenience fns' => sub {
            it 'should count which needles can be found in a haystack ' => sub {
                my $haystack = [ qw/a b c d e/ ];
                my $needle = [ qw/a c e/ ];

                my $counted_sets = Honeydew::Queue::Nightly::_set_count( $haystack, $needle );
                is_deeply($counted_sets, {
                    a => 1,
                    b => 0,
                    c => 1,
                    d => 0,
                    e => 1
                });
            };

            it 'should return the missing needles from a haystack' => sub {
                my $haystack = { a => 1, b => 0, c => 1, d => 0 };

                my $missing = Honeydew::Queue::Nightly::_get_missing( $haystack );
                is_deeply( $missing, [ qw/b d/ ] );
            };
        };
    };

    describe 'features' => sub {

        it 'should get features from a list of set files' => sub {
            my $nightly = Honeydew::Queue::Nightly->new(
                dbh => $dbh,
                config => $config,
                sets_to_run => [
                    'fixture.set',
                    'empty_fixture.set',
                    'not_a_file.set'
                ]
            );
            my $expected_features = $nightly->expected_features();

            is_deeply( $expected_features->{'empty_fixture.set'}, [] );
            is_deeply( $expected_features->{'not_a_file.set'}, [] );
            is_deeply( $expected_features->{'fixture.set'}, [ 'fake.feature' ] );
        };

    };
};

sub mock_expected_sets {
    my ($dbh) = @_;

    $dbh->{mock_add_resultset} = {
        sql => 'SELECT `set` as setName,`host`,`browser` FROM monitor WHERE `on` = 1',
        results => [
            [ 'setName'        , 'host'            , 'browser'            ],
            [ 'fake.set'       , 'fake host'       , 'fake browser'       ],
            [ 'other_fake.set' , 'other fake host' , 'other fake browser' ],
        ]
    };
}

sub mock_actual_sets {
    my ($dbh) = @_;

    $dbh->{mock_add_resultset} = {
        sql => 'SELECT id,setName,host,browser FROM setRun WHERE `userId` = 2 AND `startDate` >= now() - INTERVAL 12 HOUR;',
        results => [
            [ 'id' , 'setName', 'host', 'browser' ],
            [ 1    , 'fake.set', 'fake host', 'fake browser' ]
        ]
    };
}

runtests;
