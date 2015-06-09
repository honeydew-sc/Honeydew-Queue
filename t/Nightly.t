#! /usr/bin/perl

use strict;
use warnings;
use DBD::Mock;
use DBI;
use Test::Spec;

use Honeydew::Queue::Nightly;

describe 'Nightlies' => sub {
    my ($nightly, $dbh);

    $dbh = DBI->connect( 'DBI:Mock:', '', '' )
      || die "Cannot create handle: $DBI::errstr\n";

    before each => sub {
        $nightly = Honeydew::Queue::Nightly->new(
            dbh => $dbh
        );
    };

    it 'should ask the monitor table for expected sets' => sub {
        $dbh->{mock_add_resultset} = {
            sql => 'SELECT `set` as setName,`host`,`browser` FROM monitor WHERE `on` = 1',
            results => [
                [ 'setName'        , 'host'            , 'browser'            ],
                [ 'fake.set'       , 'fake host'       , 'fake browser'       ],
                [ 'other_fake.set' , 'other fake host' , 'other fake browser' ],
            ]
        };

        my $expected_sets = $nightly->expected_sets;
        is( $expected_sets->[0], 'fake.set fake host fake browser' );
        is( $expected_sets->[1], 'other_fake.set other fake host other fake browser' );
    };

    after_each => sub {
        $dbh->{mock_clear_history} = 1;
    };
};



runtests;
