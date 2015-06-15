package Honeydew::Queue::JobRunner;

# ABSTRACT: Dispatch manual and resque Honeydew jobs
use strict;
use warnings;
use Exporter;
use Try::Tiny;
use Resque;
use Honeydew::Config;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(run_job args_to_options_hash);

my $config = Honeydew::Config->instance;
my $features_dir = $config->features_dir;
my $sets_dir = $config->sets_dir;
my $hdew_bin = $config->{honeydew}->{basedir} . "bin";
my $hdew_lib = $config->{honeydew}->{basedir} . "lib";

sub run_job {
    my($args) = shift || return;
    my($test) = shift || "";

    my(%data) = args_to_options_hash($args);

    if ((!$data{feature} && !$data{setName}) || !$data{host} || !$data{user}) {
        my $error_msg = "ERROR: $args: feature: " . $data{feature} .
          ", host: " . $data{host} .
          ", user: " . $data{user};
        job_log($error_msg);
        return();
    }

    my $libs = $config->{perl}->{libs};
    my @libs = grep $_, split(/\s*-I\s*/, $libs);

    my @non_sudo_libs = (
        $hdew_lib,
        "/home/honeydew/perl5/lib/perl5",
    );

    my $base_command = "perl ";
    foreach (@non_sudo_libs, @libs) {
        $base_command .= " -I$_ " if -d $_;
    }
    my $user = delete($data{user});
    $base_command .= " $hdew_bin/honeydew.pl -database -user=" . $user . " ";

    # If there is a feature set passed in, treat it like a group of
    # individual features. If we have a set _and_ a feature, it means
    # we're requeueing a missed feature, and we don't want to do the
    # whole set.
    if ($data{setName} && !$data{feature}) {
        $base_command .= " -local=$data{local}" if $data{local};
        $data{setName} = "$sets_dir/$data{setName}" if $data{setName} !~ /^$sets_dir/;

        update_set($data{setName});
        if (open(IN, "<", "$data{setName}")) {
            my @set_jobs;
            my(@sets) = <IN>;
            close(IN);

            # we want to avoid wasting time on empty files
            @sets = grep { chomp; -f $features_dir . "/$_" } @sets;

            foreach my $feature (@sets) {
                my $cmd = $base_command;
                $feature =~ s/\r|\n//;
                if ($feature !~ /^$features_dir/) {
                    $feature = "$features_dir/$feature";
                }

                $cmd .= " -feature=$feature";
                $cmd = append_options($cmd, \%data);

                try {
                    queue_job($cmd, $test);
                    push @set_jobs, $cmd;
                }
                catch {
                    my $error_msg = "ERROR: $_. set: $data{setName}. user: $user.\nERROR: cmd: $cmd.";
                    job_log($error_msg);
                };
            }

            maybe_start_private_worker ( $base_command, \%data );
            return @set_jobs;
        }
        else {
            job_log("Error opening set file: $data{setName} => $!");
            return "$data{setName}";
        }
    }
    else {
        # otherwise, just run the single feature
        my $cmd = $base_command;

        $cmd = append_options($cmd, \%data);

        job_log($cmd);
        system $cmd unless $test eq "test";
        return $cmd;
    }
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
    my($str) = shift || return;
    my(%h);

    my(@data) = split(/\^/, $str);

    foreach my $line (@data) {
        my($k, $v) = split(/=/, $line, 2);
        $h{$k} = $v;
    }

    return(%h);
}

sub update_set {
    my $set = shift;
    my $features = shift || $features_dir;
    my $setFilename = $set;
    $set =~ s/.*sets\/(.*)\.set$/$1/;
    my $findFeatures = 'cd ' . $features_dir . ' && grep -rl -P "^Set:.*?\b' . $set . '\b" .';
    my $setFeatures = `$findFeatures`;

    open (my $fh, ">", $setFilename);
    print $fh $setFeatures;
    close ($fh);
}

sub job_log {
    my ($msg) = @_;

    my $now = localtime;
    $msg = '[' . $now . '] ' . $msg;

    `echo '$msg' >> $hdew_bin/job.log`;
}

sub choose_queue {
    my $cmd = shift || return;

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
        return $config->{redis}->{redis_background_channel};
    }
}

sub queue_job {
    my ($cmd, $test) = @_;

    my $r = Resque->new( redis => $config->redis_addr );
    my $queue = choose_queue($cmd);

    my $res = $r->push( $queue => {
        class => 'Honeydew::Job',
        args => [{
            cmd => $cmd,
            test => $test
        }]
    });

    if ($cmd =~ /croneydew/i) {
        job_log("SET QUEUE: $res, add $cmd");
    }
}

sub maybe_start_private_worker {
    my ($base, $data) = @_;
    my $queue = choose_queue(append_options($base, $data));

    my $background_channel = $config->{redis_background_channel};
    # Start up an individual worker for each set with a channel. We
    # don't want two workers on a single set, because things will run
    # out of order and the output will be garbled. We don't want to
    # share a single set's workers with other users, because users
    # want their sets to run immediately.
    if ($queue =~ /^private\-/) {
        local @ARGV = ( $queue );
        my $ret = do $hdew_bin . '/manual_set_worker.pl';
    }

    # If there is no channel on the job, we can let our background
    # workers take care of it; they manage themselves, so we don't
    # have to do anything.
}

1;
