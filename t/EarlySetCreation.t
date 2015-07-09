use Test::Spec;
use Honeydew::Queue::JobRunner;

my $runner = Honeydew::Queue::JobRunner->new;

describe 'Early set report creation' => sub {
    my (%values);

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
