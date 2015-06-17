package Honeydew::Queue::JobRunner;

# ABSTRACT: Dispatch manual and resque Honeydew jobs
use strict;
use warnings;
use feature qw/state say/;
use Cwd qw/abs_path/;
use Try::Tiny;
use Resque;
use Honeydew::Config;
use Moo;

has config => (
    is => 'lazy',
    default => sub {
        return Honeydew::Config->instance;
    }
);

has features_dir => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $config = $self->config;
        return $config->features_dir;
    }
);

has sets_dir => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $config = $self->config;
        return $config->sets_dir;
    }
);

has hdew_bin => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $config = $self->config;
        return $config->{honeydew}->{basedir} . "/bin";
    }
);

has hdew_lib => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        my $config = $self->config;
        return $config->{honeydew}->{basedir} . "/lib";
    }
);

has resque => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;
        return Resque->new( redis => $self->config->redis_addr );
    }
);

has _base_command => (
    is => 'lazy',
    default => sub {
        my ($self) = @_;

        my $libs = $self->config->{perl}->{libs} || '';
        my @libs = grep $_, split(/\s*-I\s*/, $libs);

        my @non_sudo_libs = (
            $self->hdew_lib,
            "/home/honeydew/perl5/lib/perl5",
        );

        my $base_command = "perl ";
        foreach (@non_sudo_libs, @libs) {
            $base_command .= " -I$_ " if -d $_;
        }

        return $base_command;
    }
);

sub run_job {
    my ($self, $args, $test) = @_;
    $test //= '';

    my(%data) = $self->args_to_options_hash($args);
    my $base_command = $self->construct_base_command( %data );

    my $sets_dir = $self->sets_dir;
    my $features_dir = $self->features_dir;
    # If there is a feature set passed in, treat it like a group of
    # individual features. If we have a set _and_ a feature, it means
    # we're requeueing a missed feature, and we don't want to do the
    # whole set.
    if ($data{setName} && !$data{feature}) {
        $base_command .= " -local=$data{local}" if $data{local};
        $data{setName} = abs_path("$sets_dir/$data{setName}") if $data{setName} !~ /^$sets_dir/;

        update_set($data{setName}, $features_dir);
        if (open(IN, "<", "$data{setName}")) {
            my @set_jobs;
            my(@sets) = <IN>;
            close(IN);

            # we want to avoid wasting time on empty files
            @sets = grep { chomp; -f $features_dir . "/$_" } @sets;

            foreach my $feature (@sets) {
                my $validated_feature = $self->validate_feature( $feature );
                next unless $validated_feature;

                my %this_data = %data;
                $this_data{feature} = $validated_feature;

                my $cmd = $self->prepare_and_queue( $base_command, \%this_data, $test );
                push @set_jobs, $cmd;
            }

            return @set_jobs;
        }
        else {
            $self->log("Error opening set file: $data{setName} => $!");
            return "$data{setName}";
        }
    }
    else {
        return $self->prepare_and_queue( $base_command, \%data, $test );
    }
}

sub validate_feature {
    my ($self, $feature) = @_;
    my $features_dir = $self->features_dir;

    $feature =~ s/\r|\n//;
    if ($feature !~ /^$features_dir/) {
        $feature = "$features_dir/$feature";
        $feature = abs_path($feature);
    }

    return $feature;
}

sub prepare_and_queue {
    my ($self, $cmd, $data, $test) = @_;

    $cmd = append_options($cmd, $data);
    $self->queue_job($cmd, $test);
    return $cmd;
}

sub append_options {
    my ($string, $data) = @_;

    # shallow copy options to preserve sauce=true across multiple
    # features as part of set jobs
    my $options = { %$data };

    $string .= delete($options->{sauce}) ? " -sauce" : "";

    foreach (keys %$options) {
        my $val = $options->{$_};
        my $q =  $val =~ / / ? '"' : '';
        $string .= " -" . $_ . "=". $q . $val . $q;
    }

    return $string;
}

sub args_to_options_hash {
    my($self, $str) = @_;

    my(%data);
    my(@data) = split(/\^/, $str);

    foreach my $line (@data) {
        my($k, $v) = split(/=/, $line, 2);
        $data{$k} = $v;
    }

    if ((!$data{feature} && !$data{setName}) || !$data{host} || !$data{user}) {
        my $error_msg = "ERROR $str: feature: " . $data{feature} .
          ", host: " . $data{host} .
          ", user: " . $data{user};
        $self->log($error_msg);
        die $error_msg;
    }

    return(%data);
}

sub update_set {
    my ($set, $features_dir) = @_;

    my $setFilename = $set;
    $set =~ s/.*sets\/(.*)\.set$/$1/;
    my $findFeatures = 'cd ' . $features_dir . ' && grep -rl -P "^Set:.*?\b' . $set . '\b" .';
    my $setFeatures = `$findFeatures`;

    open (my $fh, ">", $setFilename);
    print $fh $setFeatures;
    close ($fh);
}

sub log {
    my ($self, $msg) = @_;
    my $hdew_bin = $self->hdew_bin;

    my $now = localtime;
    $msg = '[' . $now . '] ' . $msg;

    `echo '$msg' >> $hdew_bin/job.log`;
}

sub choose_queue {
    my $cmd = shift || return;
    my $config = Honeydew::Config->instance;

    my ($user) = $cmd =~ m/-user=(\w+)/;
    my ($channel) = $cmd =~ m/-channel=(private-\w{8})/;
    my ($local) = $cmd =~ m/-local=((?:\d{1,3}.?){4})/;

    if ($channel) {
        return $channel . $user;
    }
    elsif ($local) {
        $local =~ s/^\s+|\s+$//g;
        my $local_addresses = { reverse %{ $config->{local}} };
        return $local_addresses->{$local};
    }
    else {
        return $config->{redis}->{redis_background_channel} || 'no_channel';
    }
}

sub queue_job {
    my ($self, $cmd, $test) = @_;

    my $r = $self->resque;
    my $queue = choose_queue($cmd);

    $self->log($cmd);
    my $res = $r->push( $queue => {
        class => 'Honeydew::Job',
        args => [{
            cmd => $cmd,
            test => $test
        }]
    });

    if ($cmd =~ /croneydew/i) {
        $self->log("SET QUEUE: $res, add $cmd");
    }
}

sub construct_base_command {
    my ($self, %data) = @_;

    my $base_command = $self->_base_command;

    my $user = delete($data{user});
    my $hdew_bin = $self->hdew_bin;
    $base_command .= " $hdew_bin/honeydew.pl -database -user=" . $user . " ";

    return $base_command;
}

1;
