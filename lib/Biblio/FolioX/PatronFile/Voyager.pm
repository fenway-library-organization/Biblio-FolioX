package Biblio::FolioX::PatronFile::Voyager;

use strict;
use warnings;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile);

use Biblio::SIF::Patron;
use Fcntl qw(:seek);
use JSON;
use Data::UUID;

*_req = Biblio::FolioX::PatronFile::_req;
*_opt = Biblio::FolioX::PatronFile::_opt;

sub new {
    my $cls = shift;
    unshift @_, 'file' if @_ == 1;
    my $self = bless { @_ }, $cls;
    $self->init;
    return $self;
}

sub init {
    my ($self) = @_;
    my $ug = Data::UUID->new;
    $self->{'uuidgen'} = sub {
        return $ug->create_str;
    };
    return $self;
}

sub _open {
    my ($self, $file) = @_;
    open my $fh, '<', $file
        or $self->_error("open $file: $!");
    binmode $fh;
    return $self->{'fh'} = $fh;
}

sub iterate {
    my ($self, $func, %arg) = @_;
    %$self = ( %$self, 'index' => {}, %arg );  # Clear the index if it exists
    my $file = $self->{'file'}
        or $self->_error("no file specified");
    my $fh = $self->_open($file);
    my $term = "\n";  # Safest bet
    if (seek($fh, 0, SEEK_SET)) {
        my $buf;
        if (read($fh, $buf, 5400)) {
            $term = $1 if /([\r\n\x00]+)/ms;
            seek($fh, 0, SEEK_SET)
                or $self->_error("seek to beginning of file $file: $!");
        }
        else {
            return if eof $fh;
        }
    }
    my $sifiter = Biblio::SIF::Patron->iterator(
        $fh,
        'terminator' => $term,
    );
    while (1) {
        my $patron = $sifiter->();
        last if !defined $patron;
        $func->($self->convert($patron));
    }
}

sub convert {
    my ($self, $patron) = @_;
    $patron = $patron->as_hash;
    my ($fn, $mn, $ln, $barcode) = @$patron{qw(first_name middle_name last_name barcode1)};
    my ($iid, $pg) = @$patron{qw(institution_id group1)};
    my @addresses;
    my ($email, $phone, $cell);
    foreach my $addr (@$patron{qw(address1 address2 address3)}) {
        my $type = $addr->{'type'}
            or next;
        if ($type == 1) {
            # Permanent
            $phone ||= $addr->{'phone'};
            $cell ||= $addr->{'cell_phone'};
            push @addresses, $self->address($addr);
        }
        elsif ($type == 2) {
            # Temporary
            $phone ||= $addr->{'phone'};
            $cell ||= $addr->{'cell_phone'};
            push @addresses, $self->address($addr);
        }
        elsif ($type == 3) {
            # E-mail
            $email = $addr->{'line1'};
        }
    }
    $self->_try(sub {
        my $uuidmap = $self->{'uuidmap'}
            or die "no UUID map";
        +{
            _req('id' => $self->uuidgen),
            _req('username' => $iid),
            _req('externalSystemId' => $iid),
            _opt('barcode' => $barcode),
            _req('active' => $patron->{'status1'} == 1 ? 1 : 0),
            _req('type' => 'somerandomstring'),
            _req('patronGroup' => $uuidmap->{'patronGroup:'.$pg}),
            _opt('enrollmentDate' => $patron->{'begin_date'}),
            _opt('expirationDate' => $patron->{'end_date'}),
            'personal' => {
                _req('lastName' => $ln),
                _opt('firstName' => $fn),
                _opt('middleName' => $mn),
                _opt('email' => $email),
            },
            'addresses' => \@addresses,
        }
    });
}

sub address {
    my ($self, $addr) = @_;
    my $type = $addr->{'type'};  # 1 (primary), 2 (secondary)
    $self->_try(sub {
        +{
            _req('addressTypeId' => $type == 1 ? 'Campus' : 'Home'),
            _req('primaryAddress' => $type == 1 ? 1 : 0),
            _opt('addressLine1' => $addr->{'line1'}),
            _opt('addressLine2' => $addr->{'line2'}),
            _opt('city' => $addr->{'city'}),
            _opt('region' => $addr->{'state'}),
            _opt('postalCode' => $addr->{'zipcode'}),
            _opt('countryId' => $addr->{'country'}),
        };
    });
}

sub try {
    my ($self, $func) = @_;
    my ($ok, $res);
    eval {
        $res = $func->();
        $ok = 1;
    };
    return $res if $ok;
    my ($msg) = split /\n/, $@;
    $self->_error($msg);
}

sub uuidgen {
    my ($self) = @_;
    $self->{'uuidgen'}->();
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
