package Biblio::FolioX::PatronFile;

use strict;
use warnings;

use POSIX qw(strftime);
use Data::UUID;

sub init {
    my ($self) = @_;
    my $ug = Data::UUID->new;
    $self->{'uuidgen'} = sub {
        return $ug->create_str;
    };
    $self->{'uuidmap'} = $self->{'site'}{'uuidmap'};
    return $self;
}

sub _open {
    my ($self, $file) = @_;
    open my $fh, '<', $file
        or $self->_error("open $file: $!");
    binmode $fh;
    return $self->{'fh'} = $fh;
}

sub _uuid {
    my ($self, $obj) = @_;
    return $obj->{'id'}
        if defined $obj
        && defined $obj->{'id'};
    my $uuid = $self->{'uuidgen'}->();
    $obj->{'id'} = $uuid if defined $obj;
    return $uuid;
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
    my $each = $arg{'each'} || die "no callback";
    my $error = $arg{'error'};
    my $batch_size = $arg{'batch_size'} || 1;
    my $file = $self->{'file'};
    my $fh = $self->{'fh'} || $self->_open($file);
    my @users;
    my $n = 0;
    while (1) {
        my ($user, $ok, $err);
        eval {
            $user = $self->_next($fh);
            ($ok, $err) = (1);
        };
        if ($user) {
            $n++;
            push @users, $user;
            if (@users == $batch_size) {
                $each->(@users);
                @users = ();
            }
        }
        elsif ($ok) {
            last;
        }
        else {
            $n++;
            $error->($n) if $error;
        }
    }
    $each->(@users) if @users;
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
