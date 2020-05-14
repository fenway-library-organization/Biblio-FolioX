package Biblio::FolioX::PatronFile;

use strict;
use warnings;

use POSIX qw(strftime);

sub init {
    my ($self) = @_;
    # $self->{'uuidmap'} = $self->{'site'}{'uuidmap'};
    return $self;
}

sub _open {
    my ($self, $file) = @_;
    open my $fh, '<', $file
        or die "open $file: $!";
    binmode $fh
        or die "binmode $file: $!";
    return $fh;
}

sub run_hooks {
    my $hooks = shift
        or return;
    my $r = ref $hooks;
    if ($r eq 'CODE') {
        $hooks->(@_);
    }
    elsif ($r eq 'ARRAY') {
        $_->(@_) for @$hooks;
    }
    else {
        die "unrunnable hook: $r";
    }
}

sub iterate {
    my $self = shift;
    local $_;
    my %arg;
    if (@_ > 1 ) {
        %arg = @_;
    }
    elsif (@_ == 1) {
        $arg{'each'} = shift @_;
    }
    my ($first, $before, $each, $error, $after, $last) = @arg{qw(first before each error after last)};
    die "no callback" if !$each;
    my $batch_size = $arg{'batch_size'} || 1;
    my $file = $arg{'file'} || $self->{'file'}
        or die "no file to iterate over";
    my $fh = $self->{'fh'} ||= $self->_open($file);
    my @batch;
    my $success = 0;
    my $n = 0;
    eval {
        while (1) {
            my ($user, $ok, $err);
            eval {
                $user = $self->next($fh);
                ($ok, $err) = (1);
            };
            if (defined $user) {
                $n++;
                push @batch, $user;
                run_hooks($first, $self) if $n == 1;
                if (@batch == $batch_size) {
                    run_hooks($before);
                    run_hooks($each, @batch);
                    run_hooks($after);
                    @batch = ();
                }
            }
            elsif ($ok) {
                last;
            }
            else {
                $n++;
                my $die = 1;
                eval {
                    run_hooks($error, $n);
                    $die = 0;
                };
            }
        }
        if (@batch) {
            run_hooks($before);
            run_hooks($each, @batch);
            run_hooks($after);
        }
        run_hooks($last, $self) if $n > 0;
        $success = 1;
    };
    delete $self->{'fh'};
    delete $self->{'file'} if !defined $arg{'file'};
    close $fh or $success = 0;
    die $@ if !$success;
    return $self;
}

sub _default_user {
    my ($self) = @_;
    return {
        'id' => undef,
        'username' => undef,
        'externalSystemId' => undef,
        'barcode' => undef,
        'active' => 1,
        'type' => undef,
        'patronGroup' => undef,
        'enrollmentDate' => undef,
        'expirationDate' => undef,
        'personal' => {
            'lastName' => undef,
            'firstName' => undef,
            'middleName' => undef,
            'email' => undef,
            'phone' => undef,
            'mobilePhone' => undef,
            'dateOfBirth' => undef,
            'addresses' => undef,
        },
    };
}

sub _req {
    my ($k, $v) = @_;
    die if !defined $v;
    return ($k => $v);
}

sub _opt {
    my ($k, $v) = @_;
    return if !defined $v;
    return ($k => $v);
}

1;
