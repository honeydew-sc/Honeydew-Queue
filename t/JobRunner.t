use strict;
use warnings;
use Test::More;
use Test::Fatal;

plan skip_all => 'Tests are not ready for outside use'
  unless -d '/opt/honeydew';

require Honeydew::Queue::JobRunner;

my $executable = "/opt/honeydew/bin/honeydew.pl";
my $feature = "/opt/honeydew/features/tests/url-regex.feature";

my $host = "http://localhost";
my $browser = "Windows 2003 - htmlunit webdriver";
my $sauce = "true";
my $user = "testdew";
my $channel = "hello";
my $size="434x343";

{
    package Null;

    my $null = bless {}, __PACKAGE__;
    sub AUTOLOAD { $null }
    1;
}

my $runner = Honeydew::Queue::JobRunner->new(
    report_class => Null->new,
    resque => Null->new
);

QUEUE: {
    my $cmd = '/usr/bin/perl  -I/opt/honeydew/lib  /opt/honeydew/bin/honeydew.pl -database -user=testdew  -feature=/opt/honeydew/features/./fake2.feature -setRunId=kqjafxdd -browser="Windows 2003 - chrome Local" -channel=private-asdfasdf -setName=/opt/honeydew/sets/testing.set -host=http://localhost';

    my $queue = Honeydew::Queue::JobRunner->choose_queue($cmd);
    cmp_ok($queue, 'eq', 'private-asdfasdf-testdew', 'private queues are named properly to allow them to auto-reap when empty');
    cmp_ok($queue, '=~', qw/testdew/, 'Job with channel and user gets put in user\'s queue');

    $cmd =~ s/asdfasdf/qwerqwer/;
    my $second_queue = Honeydew::Queue::JobRunner->choose_queue($cmd);
    cmp_ok($second_queue, 'ne', $queue, 'A user can have multiple unique set queues');

    my $config = Honeydew::Config->instance;
    if (exists $config->{local}) {
        $config->{local}->{fake_remote} = '1.2.3.4';
    }
    else {
        $config->{local} = {
            fake_remote => '1.2.3.4'
        };
    }

    # To look like a nightly job, remove channel and add local
    $cmd =~ s/-channel=private-\w{8}//;
    $cmd .= ' -local=1.2.3.4';
    my $nightly_queue = Honeydew::Queue::JobRunner->choose_queue($cmd);
    cmp_ok($nightly_queue, 'eq', 'fake_remote', 'Jobs without channels are background/nightlies and should be queued by box name');
}

QUEUE_IOS: {
  IS_IOS: {
        my $cmd = '-browser="iOS Mobile Safari Local"';
        ok( $runner->is_real_ios($cmd), 'we can determine a real iOS job' );
    }

  INVALID: {
        my $cmd = '-browser="iOS Mobile Safari Local';
        ok( exception { $runner->choose_queue($cmd) },
            'we cannot run real iOS without a local addr' );
    }

  VALID: {
        # The trailing space is important, as the previous regex was
        # incorrectly picking it up and leading to issues for queue
        # name.
        my $ios_cmd = '-browser="52 iOS Mobile Safari Local" -local=1.2.3.4 ';

        my $queue = $runner->choose_queue($ios_cmd);
        is($queue, 'ios_1.2.3.4', 'we can choose the appropriate queue for an iOS job');
    }
}

SET: {
    my $setName = 'testing';
    my $set = '/opt/honeydew/sets/' . $setName . '.set';
    unlink $set;

    my @fakeFeatures = qw/fake1 fake2/;

    foreach (@fakeFeatures) {
        if ($_ eq 'fake2') {
            $setName = '@' . $setName;
        }
        open (my $fh, ">", '/opt/honeydew/features/' . $_ . '.feature');
        print $fh 'Feature: sample
Set: ' . $setName;
        close ($fh);
    }

    my $setRunId = '123456789';
    my @job = (
        "setName=$set",
        "host=$host",
        "user=$user",
        "browser=$browser",
        "setRunId=$setRunId",
        "sauce=true",
        "channel=private-asdfasdf"
    );

    my @setJobs = $runner->run_job(join('^', @job), "test");
    cmp_ok(scalar @setJobs, '==', 2, 'skip nonexistent files');
    my $command = $setJobs[0];

    cmp_ok($command, "=~", qr/$executable/, "standard opt is constructed correctly");
    cmp_ok($command, "=~", qr/ \-database/, "standard database is constructed correctly");
    cmp_ok($command, "=~", qr/ \-user=$user/, "standard user is constructed correctly");
    cmp_ok($command, "=~", qr/fake1/, "standard feature is constructed correctly");
    cmp_ok($command, "=~", qr/ \-host=$host/, "standard host is constructed correctly");
    cmp_ok($command, "=~", qr/ \-sauce(?!=true)/, "standard sauce is constructed correctly");
    cmp_ok($command, "=~", qr/ \-browser="$browser"/, "standard browser is constructed correctly");

    cmp_ok($setJobs[0], '=~', qr/-channel=private/i, 'channel gets put on the individial executions');

    cmp_ok($setJobs[1], '=~', qr/fake2/, 'fake2.feature with @testing as set is included');
    cmp_ok($setJobs[1], '=~', qr/ \-sauce/, 'all jobs in set are sauced appropriately');

    # cleanup
    foreach (@fakeFeatures) {
        unlink '/opt/honeydew/features/' . $_ . '.feature';
    }

    unlink $set;
}

REPLACE_FEATURE: {
    my $reportId = '123456789';
    my $job = "feature=$feature^host=$host^user=$user^browser=$browser^reportId=$reportId^size=$size";
    my $replaceJob = $runner->run_job($job, "test");

    cmp_ok($replaceJob, "=~", qr/ \-reportId=.*$reportId/, "reportId is added correctly for single replace jobs");
    cmp_ok($replaceJob, "=~", qr/ \-size=$size/, "size is added correctly for single replace jobs");
}

REPLACE_MISSING_FEATURE: {
    my $job = "feature=/opt/honeydew/features/test/dan.feature^host=http://www.sharecare.com^setName=sets/examples.set^setRunId=47^user=dgempesaw^local=127.0.0.2^browser=chrome local";
    my $replace = $runner->run_job($job, 'test');
    cmp_ok($replace, '=~', qr%-setName=sets/examples.set -setRunId=47%, 'missing feature replacements pass through set name and set run');
}

FEATURE: {
    my $job = "feature=$feature^host=$host^user=$user^sauce=true^browser=$browser";
    my $command = $runner->run_job($job, "test");

    cmp_ok($command, "=~", qr/$executable/, "standard opt is constructed correctly");
    cmp_ok($command, "=~", qr/ \-database/, "standard database is constructed correctly");
    cmp_ok($command, "=~", qr/ \-user=$user/, "standard user is constructed correctly");
    cmp_ok($command, "=~", qr/ \-feature=$feature/, "standard feature is constructed correctly");
    cmp_ok($command, "=~", qr/ \-host=$host/, "standard host is constructed correctly");
    cmp_ok($command, "=~", qr/ \-sauce/, "standard sauce is constructed correctly");
    cmp_ok($command, "=~", qr/ \-browser="$browser"/, "standard browser is constructed correctly");
    cmp_ok($command, '!~', qr/channel/, "normally doesn't get channel");

    $job = "feature=$feature^host=$host^user=$user^channel=$channel^browser=$browser";
    $command = $runner->run_job($job, "test");

    cmp_ok($command, "!~", qr/sauce/, "sauce doesn't show up when we don't expect it");
    cmp_ok($command, "=~", qr/ \-channel=$channel/, "standard channel is constructed correctly");
}

REQUEUE_FEATURE: {
    my $job = "feature=$feature^host=$host^user=$user^browser=$browser^setName=setName";
    my $ret = $runner->run_job($job, "test");
    ok($ret, 'we can requeue a job by its setName and only run one feature');
}

done_testing;
