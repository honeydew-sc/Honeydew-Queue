#! /usr/bin/perl

use strict;
use warnings;
use DBD::Mock;
use DBI;
use File::Temp qw/ tempfile /;
use File::Basename qw/ dirname /;
use File::Spec;
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
            is( $expected_sets->[0], 'fake.set fake_host fake_browser' );
            is( $expected_sets->[1], 'other_fake.set other_fake_host other_fake_browser' );
        };

        describe 'all-runner' => sub {
            it 'should not query the setRun table when running all' => sub {
                my $run_all_nightly = Honeydew::Queue::Nightly->new(
                    dbh => $dbh,
                    config => $config,
                    run_all => 1
                );
                is_deeply( $run_all_nightly->actual_sets, {} );
            };

            it 'should determine run all on its own' => sub {
                @ARGV = qw/ execute all /;
                my $run_all_nightly = Honeydew::Queue::Nightly->new(
                    dbh => $dbh,
                    config => $config
                );

                ok( $run_all_nightly->run_all );
            };

            after each => sub { @ARGV = () };
        };

        it 'should query the setRun table for existing sets' => sub {
            mock_actual_sets( $dbh );
            my $actual_sets = $nightly->actual_sets;
            is_deeply( $actual_sets, { 1 => 'fake.set fake_host fake_browser' });
        };

        it 'should get a proper list of the sets to be queued' => sub {
            mock_expected_sets( $dbh );
            mock_actual_sets( $dbh );
            my $missing_sets = $nightly->sets_to_run;
            is( $missing_sets->[0], 'other_fake.set other_fake_host other_fake_browser' );
        };

        describe 'commands' => sub {
            my $command_nightly;

            before each => sub {
                my $sets_to_run = [
                    'fake.set fake_host fake_browser',
                    'fake2.set fake2_host AB fake_browser Local',
                    'invalid.set invalid_host invalid_browser'
                ];

                my $all_expected_features = {
                    'fake.set' => [
                        'fake.feature'
                    ],
                    'fake2.set' => [
                        'fake.feature'
                    ]
                };

                my $config = {
                    local => {
                        AB => '1.2.3.4'
                    }
                };

                $command_nightly = Honeydew::Queue::Nightly->new(
                    sets_to_run => $sets_to_run,
                    all_expected_features => $all_expected_features,
                    config => $config
                );
            };

            it 'should get a validated list of set commands to run' => sub {
                my $cmds = $command_nightly->set_commands_to_run;
                like($cmds->[0], qr/setRunId=.*?\^user=croneyDew\^browser=fake_browser \(set\)\^setName=fake.set\^host=fake_host/);
            };

            it 'should include the local address if applicable' => sub {
                my $cmds = $command_nightly->set_commands_to_run;
                like($cmds->[1], qr/\^local=1\.2\.3\.4/);
            };

            it 'should only include sets with features' => sub {
                my $cmds = $command_nightly->set_commands_to_run;
                # There are 3 sets to run, but only 2 in features to
                # run, so we should be dropping the invalid one.
                is( scalar @$cmds, 2 );
            };


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
            my $expected_features = $nightly->all_expected_features;

            is_deeply( $expected_features->{'empty_fixture.set'}, [] );
            is_deeply( $expected_features->{'not_a_file.set'}, [] );
            is_deeply( $expected_features->{'fixture.set'}, [ 'fake.feature' ] );
        };

        it 'should query the database for actually executed features' => sub {
            my $nightly = Honeydew::Queue::Nightly->new(
                dbh => $dbh,
                config => $config,
                actual_sets => {
                    1 => 'actual.set'
                }
            );

            mock_actual_features( $dbh );
            my $actual_features = $nightly->actual_features;
            is_deeply( $actual_features,
                       { 'actual.set' => [ 'executed.feature' ] } );
        };

    };
};

sub mock_expected_sets {
    my ($dbh) = @_;

    $dbh->{mock_add_resultset} = {
        sql => 'SELECT `set` as setName,`host`,`browser` FROM monitor WHERE `on` = 1',
        results => [
            [ 'setName'        , 'host'            , 'browser'            ],
            [ 'fake.set'       , 'fake_host'       , 'fake_browser'       ],
            [ 'other_fake.set' , 'other_fake_host' , 'other_fake_browser' ],
        ]
    };
}

sub mock_actual_sets {
    my ($dbh) = @_;

    $dbh->{mock_add_resultset} = {
        sql => 'SELECT id,setName,host,browser FROM setRun WHERE `userId` = 2 AND `startDate` >= now() - INTERVAL 12 HOUR;',
        results => [
            [ 'id' , 'setName', 'host', 'browser' ],
            [ 1    , 'fake.set', 'fake_host', 'fake_browser' ]
        ]
    };
}

sub mock_actual_features {
    my ($dbh) = @_;

    $dbh->{mock_add_resultset} = {
        sql => 'SELECT featureFile from report where setRunId = ?',
        results => [
            [ 'featureFile'      ],
            [ 'executed.feature' ]
        ]
    };
}

runtests;
