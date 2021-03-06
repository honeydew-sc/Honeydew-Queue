package Honeydew::Queue::Nightly;

# ABSTRACT: Accumulate sets and features for nightly enqueueing
use Moo;
use feature qw/state say/;
use Cwd qw/abs_path/;
use File::Spec;
use Honeydew::Config;
use Honeydew::Queue::JobRunner;
use Resque;

has dbh => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;

        require DBI;
        require DBD::mysql;

        my $dbh = DBI->connect( $self->config->mysql_dsn );

        return $dbh;
    }
);

has config => (
    is => 'lazy',
    default => sub { return Honeydew::Config->instance }
);

has resque => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $redis_addr = $self->config->redis_addr;

        return Resque->new( redis => $redis_addr );
    },
    predicate => 1
);

has job_runner => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $resque = $self->resque;

        return Honeydew::Queue::JobRunner->new(
            resque => $resque
        );
    }
);

has run_all => (
    is => 'lazy',
    default => sub {
        return 0 unless scalar @ARGV >= 2;
        return $ARGV[1] eq 'all';
    }
);

has execute => (
    is => 'lazy',
    default => sub { 0 }
);

has sets_to_run => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;

        my $expected_sets = $self->expected_sets;
        my $actual_sets = $self->actual_sets;

        my $set_count = _set_count($expected_sets, [ values %{ $actual_sets } ] );
        my $missing_sets = _get_missing($set_count);

        return $missing_sets;
    }
);

sub expected_sets {
    my ($self) = @_;
    my $dbh = $self->dbh;

    # cache the expected steps to avoid unnecessary db calls
    state $expected;
    return $expected if $expected;

    my @fields = (
        '`set` as setName',
        '`host`',
        '`browser`'
    );

    my $sth = $dbh->prepare('SELECT ' . join (',', @fields) . ' FROM monitor WHERE `on` = 1');
    $sth->execute;
    $expected = [
        map _concat($_),  @{ $sth->fetchall_arrayref }
    ];

    return $expected;
}

has actual_sets => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my ($dbh) = $self->dbh;

        return {} if $self->run_all;

        my @fields = qw/id setName host browser/;
        my $sth = $dbh->prepare('SELECT ' . join(',', @fields) . ' FROM setRun WHERE `userId` = 2 AND `startDate` >= now() - INTERVAL 12 HOUR;');
        $sth->execute;
        my $results = $sth->fetchall_arrayref;

        return {
            map {
                my ($monitor) = $_;
                my $id = shift @{ $monitor };
                $id => _concat($monitor);
            } @{ $results }
        };
    }
);

sub _concat {
    my ($aref, $sep) = @_;
    $sep ||= ' ';

    return join( $sep , @{ $aref } );
}

sub _set_count {
    my ($expected, $actual) = @_;

    my %count = map { $_ => 0 } @$expected;
    foreach (@$actual) {
        $count{$_}++;
    }

    return \%count;
}

sub _get_missing {
    my ($count_hash) = @_;

    return [ sort grep { not $count_hash->{$_} } keys %$count_hash ];
}

has all_expected_features => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my @sets = @{ $self->sets_to_run };

        # the $sets aref has the set name, host, and browser join(' ')'d
        my @set_filenames = map _get_set_name($_), @sets;

        my $features = { map {
            my $files = $self->_get_files($_);
            if ($files) {
                $_ => $files
            }
        } @set_filenames };

        return $features;
    }
);

sub _get_set_name {
    my ($concatted) = @_;

    my @set = split(' ', $concatted);
    return shift @set;
}

sub _get_files {
    my ($self, $name) = @_;

    my $sets_dir = $self->config->sets_dir;
    my $filename = File::Spec->catfile($sets_dir, $name);
    return [] unless -f $filename;

    open (my $fh, '<', $filename);
    my (@file) = <$fh>;
    close ($fh);

    @file = map {
        chomp;
        $_ =~ s/^\.\///;
        $_
    } @file;

    return \@file;
}

has set_commands_to_run => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;

        # set job is "setName host browser" simply concatenated
        my ($set_jobs) = $self->sets_to_run;

        # A hash: keys are set names, values are features read from
        # the appropriate set file.
        my ($features_in_sets) = $self->all_expected_features;

        my @rerun;
        foreach my $set_job (@$set_jobs) {
            my $set = _get_set_name($set_job);
            if (exists $features_in_sets->{$set}) {
                my $job = $self->_job_from_monitor($set_job);
                push(@rerun, _get_command($job));
            }
        }

        return \@rerun;
    }
);

sub _job_from_monitor {
    my ($self, $monitor, $config) = @_;

    $monitor =~ s/  / /g;
    my ($set, $host, $browser) = split(' ', $monitor, 3);

    return {
        setName  => $set,
        host     => $host,
        browser  => $browser . ' (set)',
        user     => 'croneyDew',
        setRunId => _set_run_id(),
        %{ $self->_get_wd_server($browser, $config) }
    };
}

sub _set_run_id {
    my @chars = (0..9, 'a'..'z');
    my $string;

    $string .= $chars[rand @chars] for 1..8;

    return $string;
}

sub _get_wd_server {
    my ($self, $browser) = @_;
    my $local = $self->config->{local};

    my $local_by_abbrev = {
        map {
            my $key = [ split('_', $_) ];
            $key = pop(@$key);
            uc $key => $local->{$_}
        } keys %$local
    };

    if ($browser =~ /^(..) .* Local$/i) {
        my $server = $1;
        return { local => $local_by_abbrev->{$server} };
    }
    else {
        return {};
    }
}

sub _get_command {
    my ($job) = @_;

    my $job_string = join('^', map {
        $_ . '=' . $job->{$_}
    } sort keys %$job );

    return $job_string;
}

has feature_run_status => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;

        my $expected_features = $self->all_expected_features;
        my $actual_features = $self->actual_features;
        my $actual_sets = $self->actual_sets;

        my $missing_features = missing_features( $expected_features, $actual_features, $actual_sets );

        return $missing_features;
    }
);

sub actual_features {
    my ($self) = @_;
    my $dbh = $self->dbh;
    my $sets = $self->actual_sets;

    my $executed_features_by_set;
    my $sth = $dbh->prepare('SELECT featureFile from report where setRunId = ?');

    foreach (keys %$sets) {
        $sth->execute( $_ );
        my $actually_executed = [
            map {
                # trim leading /./ from database records
                $_ =~ s/^\/\.\///;
                $_
            } keys %{ $sth->fetchall_hashref('featureFile') }
        ];
        $executed_features_by_set->{$sets->{$_}} = $actually_executed;
    }

    return $executed_features_by_set;
}

sub missing_features {
    my ($expected_features, $actual_features, $actual_sets) = @_;

    my @sets_missing_features = grep {
        my $monitor = $_;
        my $set = _get_set_name($monitor);

        my $expected_size = scalar @{ $expected_features->{$set} };
        my $actual_size = scalar @{ $actual_features->{$monitor} };

        $expected_size > $actual_size
    } values %$actual_sets;

    my $sets_to_ids = { reverse %$actual_sets };

    my $feature_count;
    foreach my $monitor (@sets_missing_features) {
        my $set = _get_set_name($monitor);

        my $count = _set_count($expected_features->{$set}, $actual_features->{$monitor});
        my $key = $sets_to_ids->{$monitor} . ' ' . $monitor;
        $feature_count->{$key} = $count;
    }

    return $feature_count;
}

has feature_commands_to_run => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $dbh = $self->dbh;
        my $missing_features = $self->feature_run_status;

        my @rerun;
        my $sth = $dbh->prepare('SELECT setRunUnique as setRunId from setRun where id = ?');

        my $features_dir = $self->config->features_dir;
        foreach (keys %$missing_features) {
            my ($id, $monitor) = split(' ', $_, 2);
            my $metadata = $self->_job_from_monitor($monitor);

            # The already has a pre-existing setRunId; we need to provide
            # it to the feature so it knows what to do
            $sth->execute($id);
            my $setRunId = $sth->fetchrow_arrayref->[0];
            $metadata->{setRunId} = $setRunId;

            my $features = $missing_features->{$_};
            my $skipped_features = _get_missing($features);

            foreach (@$skipped_features) {
                my $job = $metadata;
                $job->{feature} = abs_path($features_dir . "/" . $_);

                push(@rerun, _get_command($job) );
            }
        }

        return \@rerun;
    }
);

sub all_commands_to_run {
    my ($self) = @_;

    my $sets = $self->set_commands_to_run;
    my $features = $self->feature_commands_to_run;

    my @commands = ( @$sets, @$features );

    return \@commands;
}

sub enqueue_all {
    my ($self) = @_;
    my $runner = $self->job_runner;

    my $commands = $self->all_commands_to_run;

    if ($self->execute) {
        $runner->run_job( $_ ) for @$commands;
    }
    else {
        say $_ for @$commands;
    }
}

1;
