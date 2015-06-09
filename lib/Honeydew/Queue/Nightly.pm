package Honeydew::Queue::Nightly;

# ABSTRACT: Accumulate sets and features for nightly enqueueing
use Moo;
use feature qw/state/;
use Honeydew::Config;

has dbh => (
    is => 'lazy',
    default => sub {
        my $settings = Honeydew::Config->instance->{mysql};

        require DBI;
        # require DBD::mysql;

        my $dbh = DBI->connect(
            'DBI:mysql:database=' . $settings->{database}
            . ';host=' . $settings->{host},
            $settings->{username},
            $settings->{password},
            { RaiseError => 1 }
        );

        return $dbh;
    }
);

sub get_sets_to_be_queued {
    my ($self) = @_;
    my $dbh = $self->dbh;

    my $expected_sets = $self->expected_sets;
    my $actual_sets = $self->actual_sets;

    my $set_count = set_count($expected_sets, [ values %{ $actual_sets } ] );
    my $missing_sets = get_missing($set_count);

    return $missing_sets;
}

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

sub _concat {
    my ($aref, $sep) = @_;
    $sep ||= ' ';

    return join( $sep , @{ $aref } );
}

1;
