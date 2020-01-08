package Biblio::FolioX::PatronFile::Voyager;

use strict;
use warnings;

use Biblio::FolioX::PatronFile;

use Biblio::SIF::Patron;
use Fcntl qw(:seek);
use JSON;
use Data::UUID;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile);

BEGIN {
    *Biblio::FolioX::PatronFile::Voyager::_req = *Biblio::FolioX::PatronFile::_req;
    *Biblio::FolioX::PatronFile::Voyager::_opt = *Biblio::FolioX::PatronFile::_opt;
}

sub new {
    my $cls = shift;
    unshift @_, 'file' if @_ % 2;
    my $self = bless { @_ }, $cls;
    $self->init;
    return $self;
}

sub _init_sifiter {
    my ($self, $fh) = @_;
    $self->{'fh'} = $fh;
    my $term = "\n";  # Safest bet
    if (seek($fh, 0, SEEK_SET)) {
        my $buf;
        if (read($fh, $buf, 5400)) {
            $term = $1 if $buf =~ /([\r\n\x00]+)/ms;
            seek($fh, 0, SEEK_SET)
                or die "seek: $!";
        }
    }
    return $self->{'sifiter'} = Biblio::SIF::Patron->iterator(
        $fh,
        'terminator' => $term,
    );
}

sub _next {
    my ($self, $fh) = @_;
    my $sifiter = $self->{'sifiter'};
    if (!$sifiter || $fh ne $self->{'fh'}) {
        $sifiter = $self->_init_sifiter($fh);
    }
    my $patron = $sifiter->();
    return if !defined $patron;
    return $self->_make_user($patron->as_hash);
}

sub _make_user {
    my ($self, $row) = @_;
    my $uuidmap = $self->{'uuidmap'}{'patronGroup'}
        or die "no UUID map";
    my ($fn, $mn, $ln, $barcode) = @$row{qw(first_name middle_name last_name barcode1)};
    my ($iid, $pg) = @$row{qw(institution_id group1)};
    my @addresses;
    my ($email, $phone, $cell);
    foreach my $addr (@$row{qw(address1 address2 address3)}) {
        my $type = $addr->{'type'}
            or next;
        if ($type == 1) {
            # Permanent
            $phone ||= $addr->{'phone'};
            $cell ||= $addr->{'cell_phone'};
            push @addresses, $self->_address($addr);
        }
        elsif ($type == 2) {
            # Temporary
            $phone ||= $addr->{'phone'};
            $cell ||= $addr->{'cell_phone'};
            push @addresses, $self->_address($addr);
        }
        elsif ($type == 3) {
            # E-mail
            $email = $addr->{'line1'};
        }
    }
    return {
        #_req('id' => $self->uuidgen),
        _req('username' => $iid),
        _req('externalSystemId' => $iid),
        _opt('barcode' => $barcode),
        _req('active' => $row->{'status1'} == 1 ? JSON::true : JSON::false),
        _req('type' => 'somerandomstring'),
        _req('patronGroup' => $uuidmap->{$pg}),
        _opt('enrollmentDate' => $row->{'begin_date'}),
        _opt('expirationDate' => $row->{'end_date'}),
        'personal' => {
            _req('lastName' => $ln),
            _opt('firstName' => $fn),
            _opt('middleName' => $mn),
            _opt('email' => $email),
        },
        'addresses' => \@addresses,
    };
}

sub _address {
    my ($self, $addr) = @_;
    my $type = $addr->{'type'};  # 1 (primary), 2 (secondary)
    return {
        _req('addressTypeId' => $type == 1 ? 'Campus' : 'Home'),
        _req('primaryAddress' => $type == 1 ? JSON::true : JSON::false),
        _opt('addressLine1' => $addr->{'line1'}),
        _opt('addressLine2' => $addr->{'line2'}),
        _opt('city' => $addr->{'city'}),
        _opt('region' => $addr->{'state'}),
        _opt('postalCode' => $addr->{'zipcode'}),
        _opt('countryId' => $addr->{'country'}),
    };
}

### sub uuidgen {
###     my ($self) = @_;
###     $self->{'uuidgen'}->();
### }
### 
### sub _req {
###     my ($k, $v) = @_;
###     die if !defined $v;
###     return ($k => $v);
### }
### 
### sub _opt {
###     my ($k, $v) = @_;
###     return if !defined $v;
###     return ($k => $v);
### }

1;
