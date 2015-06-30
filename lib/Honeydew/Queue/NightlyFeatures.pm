package Honeydew::Queue::NightlyFeatures;

use Moo;
use Cwd qw/abs_path/;
use List::Util qw/none/;
use Honeydew::Config;
use Honeydew::Queue::Nightly;

has sets => (
    is => 'lazy',
    handles => [ qw/ all_expected_features /],
    default => sub {
        # We just want a $nightly to look at the all of the features
        # we expect. We don't want to execute anything, and we do want
        # to assume nothing has been run.
        return Honeydew::Queue::Nightly->new(
            execute => 0,
            run_all => 1
        );
    }
);

has dbh => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $settings = $self->config->{mysql};

        require DBI;
        require DBD::mysql;

        my $dbh = DBI->connect(
            'DBI:mysql:database=' . $settings->{database}
            . ';host=' . $settings->{host},
            $settings->{username},
            $settings->{password},
            {
                RaiseError => 1 }
        );

        return $dbh;
    }
);

has config => (
    is => 'lazy',
    default => sub {
        return Honeydew::Config->instance;
    }
);

sub get_missing {
    my ($self) = @_;

    my $expected_sets = $self->all_expected_features;
    my $expected_features = $self->set_to_feature_job( $expected_sets );
    my $actual_features = $self->executed_tonight;

    my %expected_features = map { $_ => 1 } @$expected_features;

    foreach (@$actual_features) {
        delete $expected_features{$_};
    }

    return [ keys %expected_features ];
}

sub set_to_feature_job {
    my ($self, $expected_sets) = @_;

    my @all_feature_jobs = ();
    foreach my $set_job (keys %{ $expected_sets }) {
        my (undef, $host_and_browser) = split( ' ', $set_job, 2 );
        $host_and_browser =~ s/\(set\)//;
        $host_and_browser =~ s/^ +| +$//g;
        my $features = $expected_sets->{$set_job};
        my @feature_jobs = map {
            $self->clean_feature_path($_) . ' ' . $host_and_browser
        } @$features;
        push @all_feature_jobs, @feature_jobs;
    }

    return \@all_feature_jobs;
}

sub executed_tonight {
    my ($self) = @_;
    my $dbh = $self->dbh;

    my $sth = $dbh->prepare('SELECT featureFile, host, browser FROM report WHERE `userId` = 2 AND `startDate` >= now() - INTERVAL 12 HOUR');
    $sth->execute;
    my $actual = $sth->fetchall_arrayref;

    my @clean_path_actual = map {
        [ $self->clean_feature_path( $_->[0] ), $_->[1], $_->[2] ]
    } @$actual;

    return [ map Honeydew::Queue::Nightly::_concat($_), @clean_path_actual ];
}

sub clean_feature_path {
    my ($self, $feature) = @_;
    my $features_dir = $self->config->features_dir;

    $feature =~ s{/+}{/}g;
    $feature =~ s{/\./}{/}g;
    $feature =~ s{^$features_dir}{};
    $feature =~ s{^/}{};

    return $feature;
}


1;
