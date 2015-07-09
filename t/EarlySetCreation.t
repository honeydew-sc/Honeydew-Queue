use Test::Spec;
use File::Basename qw/ dirname /;
use File::Spec;
use File::Temp qw/ tempfile /;
use Sub::Install;
use Test::mysqld;
use Test::RedisServer;

use lib '/opt/honeydew/lib';
use Honeydew::Database;

plan skip_all => 'Honeydew::Reports not available'
  unless -d '/opt/honeydew/lib';

our ($mysqld, $dbh);
describe 'Early set record e2e' => sub {
  BEGIN: {
        $mysqld = Test::mysqld->new
          or skip $Test::mysqld::errstr, 1;

        $dbh = DBI->connect( $mysqld->dsn );

        Sub::Install::reinstall_sub({
            code => sub { $dbh },
            into => 'Honeydew::Database',
            as => 'getDbh'
        });
    }

    require Honeydew::Queue::JobRunner;

    my ($config, $fh, $filename, $runner);

    before all => sub {
        ($fh, $filename) = tempfile();
        print $fh qq/[header]\nkey=value/;
        close ($fh);
    };



    before all => sub {
        $config = Honeydew::Config->instance( file => $filename );
        $config->{honeydew}->{basedir} = File::Spec->catfile( dirname(__FILE__), 'fixture' );
    };

    before all => sub {
        Honeydew::Reports->createTables();
    };

    before each => sub {
        $runner = Honeydew::Queue::JobRunner->new(
            config => $config,
            dbh => $dbh,
            resque => Null->new
        );
    };

    it 'should create a set report record for a new job' => sub {
        my $job = 'setName=fake.set^host=https://www.sharecare.com^setRunId=11111111^user=honeydoer^local=127.0.0.1^browser=Chrome Local';
        # this throws because it expects the config to have queues
        # that we haven't set up. no big deal, by the time we're
        # choosing queues, we've already inserted a record.
        eval { $runner->run_job( $job, 'test' ); };

        my $sth = $dbh->prepare( 'SELECT * from setRun' );
        $sth->execute;
        my $set_record = $sth->fetchrow_hashref;

        my $expected = {
            browser => 'Chrome Local',
            deleted => 0,
            endDate => $set_record->{endDate},
            host => 'https://www.sharecare.com',
            id => 1,
            setName => $set_record->{setName},
            setRunUnique => 11111111,
            startDate => $set_record->{startDate},
            status => 'success',
            userId => 1
        };

        is_deeply( $set_record, $expected );
    };
};

describe 'Early set report creation' => sub {
      my (%values, $runner);

      before all => sub {
          $runner = Honeydew::Queue::JobRunner->new;
      };

      before each => sub {
          %values = (
              browser => 'Windows 2003 - htmlunit webdriver',
              channel => 'private-asdfasdf',
              host => 'http://localhost',
              sauce => 'true',
              setName => '/opt/honeydew/sets/testing.set',
              setRunId => '123456789',
              user => 'testdew',
              startDate => 1436392400,
              endDate => 1436392400
          );
      };

      it 'should create a set report before queueing the jobs' => sub {
          Honeydew::Reports->expects('getUserId')
              ->with( 'testdew' )
              ->returns( '1' );

          my %expected_values = (
              browser => 'Windows 2003 - htmlunit webdriver',
              channel => 'private-asdfasdf',
              endDate => 1436392400,
              host => 'http://localhost',
              sauce => 'true',
              setName => 'testing.set',
              setRunUnique => 123456789,
              startDate => 1436392400,
              status => 'success',
              user => 'testdew',
              userId => 1
          );

          Honeydew::Reports->expects('createSet')
              ->with_deep( '123456789', 'testing.set', \%expected_values )
              ->returns( '1' );

          my $ret = $runner->create_set_report( %values );
          is( $ret, 1 );
      };
  };

runtests;

undef $mysqld;
undef $dbh;

package Null {
    my $null = bless {}, __PACKAGE__;
    sub AUTOLOAD { $null }
};
