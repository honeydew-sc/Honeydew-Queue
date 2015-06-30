#! /usr/bin/perl

use strict;
use warnings;
use Test::Spec;
use DBD::Mock;
use DBI;
use File::Temp qw/tempfile/;
use File::Basename qw/dirname/;

use Honeydew::Config;
use Honeydew::Queue::NightlyFeatures;

describe 'Nightly features' => sub {
    my ($nightly_sets, $nightly_features, $config, $filename);

    my $all_expected_features = {
        'fake1.set fake_host fake_browser' => [
            'fake11.feature'
        ],
        'fake2.set other_fake_host other_fake_browser' => [
            'fake21.feature',
            'fake22.feature'
        ]
    };

    my $dbh = DBI->connect( 'DBI:Mock:', '', '' )
      || die "Cannot create handle: $DBI::errstr\n";

    my ($fh, $filename) = tempfile();
    print $fh qq/[header]\nkey=value/;
    close ($fh);
    before each => sub {
        $config = Honeydew::Config->instance( file => $filename );
        $config->{honeydew}->{basedir} = File::Spec->catfile( dirname(__FILE__), 'fixture' );
    };

    before each => sub {
        $nightly_sets = Honeydew::Queue::Nightly->new(
            execute => 0,
            run_all => 1,
            all_expected_features => $all_expected_features
        );

        $nightly_features = Honeydew::Queue::NightlyFeatures->new(
            sets => $nightly_sets,
            dbh => $dbh,
            config => $config
        );
    };

    it 'should query the db to get the executed features' => sub {
        mock_actual_features($dbh);

        my $tonight = $nightly_features->executed_tonight;
        is_deeply( $tonight, [
            'fake11.feature fake_host fake_browser',
            'fake21.feature other_fake_host other_fake_browser'
        ]);
    };

    it 'should query the queues to get the pending features' => sub {

    };

    it 'should figure out which features have not been run' => sub {
        mock_actual_features($dbh);

        my $missing = $nightly_features->get_missing;

        is_deeply($missing, [
            'fake22.feature other_fake_host other_fake_browser'
        ]);
    };

    it 'should normalize filenames from the db for comparison' => sub {
        $dbh->{mock_add_resultset} = {
            sql => 'SELECT featureFile, host, browser FROM report WHERE `userId` = 2 AND `startDate` >= now() - INTERVAL 12 HOUR',
            results => [
                [ 'featureFile'       , 'host'            , 'browser'            ],
                [ '/./fake11.feature' , 'fake_host'       , 'fake_browser'       ],
                [ '/./fake21.feature' , 'other_fake_host' , 'other_fake_browser' ],
            ]
        };

        my $missing = $nightly_features->get_missing;

        is_deeply($missing, [
            'fake22.feature other_fake_host other_fake_browser'
        ]);

    };

};

sub mock_actual_features {
    my ($dbh) = @_;

    $dbh->{mock_add_resultset} = {
        sql => 'SELECT featureFile, host, browser FROM report WHERE `userId` = 2 AND `startDate` >= now() - INTERVAL 12 HOUR',
        results => [
            [ 'featureFile'    , 'host'            , 'browser'            ],
            [ 'fake11.feature' , 'fake_host'       , 'fake_browser'       ],
            [ 'fake21.feature' , 'other_fake_host' , 'other_fake_browser' ],
        ]
    };
}

runtests;
