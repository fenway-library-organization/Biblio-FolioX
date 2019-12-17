package Biblio::FolioX::PatronFile::Millennium;

use strict;
use warnings;

use POSIX qw(strftime);
use Clone qw(clone);
use Biblio::FolioX::PatronFile;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile);

BEGIN {
    *Biblio::FolioX::PatronFile::Millennium::_req = *Biblio::FolioX::PatronFile::_req;
    *Biblio::FolioX::PatronFile::Millennium::_opt = *Biblio::FolioX::PatronFile::_opt;
}

sub new {
    my $cls = shift;
    unshift @_, 'file' if @_ % 2;
    my %arg = @_;
    my $file = $arg{'file'};
    $cls .= ($file =~ /student/i) ? '::Students' : '::Employees';
    my $self = bless { @_ }, $cls;
    $self->init;
    return $self;
}

sub _next {
    my ($self, $fh) = @_;
    my $line = <$fh>;
    return if !defined $line;
    chomp $line;
    my @row = split /\|/, $line;
    my $cols = $self->_columns;
    my $n = @$cols;
    push @row, '' while @row < $n;
    while (@row > $n) {
        die "data in extra column"
            if $row[-1] ne '';
        pop @row;
    }
    my %row = (
        '_raw' => $line,
    );
    @row{@$cols} = @row;
    return $self->_make_user(\%row);
}

sub _has_any {
    my $row = shift;
    foreach my $val (@$row{@_}) {
        return 1 if defined $val && length $val;
    }
    return 0;
}

sub _make_generic_user {
    my ($self, $row) = @_;
    my $uuidmap = $self->{'uuidmap'}{'addressType'}
        or die "no UUID map";
    my @addresses;
    my ($home, $campus) = @$uuidmap{qw(Home Campus)};
    my $user = {
        # _req('id'         => $self->_uuid),
        _req('_raw'       => $row->{'_raw'}),
        _req('personal'   => {
            _opt('firstName'   => $row->{'first_name'}),
            _opt('lastName'    => $row->{'last_name'}),
            _opt('middleName'  => $row->{'middle_initial'}),
            _opt('email'       => $row->{'email'}),
            _opt('phone'       => $row->{'home_phone'}),
            _opt('mobilePhone' => $row->{'university_phone'}),  # XXX Wrong!
            _opt('dateOfBirth' => undef),
            _opt('enrollmentDate' => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime)),
            _opt('expirationDate' => undef),
        }),
        _req('addresses'  => \@addresses),
    };
    if (_has_any($row, qw(home_address_1 home_address_2 home_city home_state home_zip_code))) {
        # Home address
        push @addresses, {
            # _req('id'           => $self->_uuid),
            _req('addressTypeId' => $home),
            _opt('addressLine1' => $row->{'home_address_1'}),
            _opt('addressLine2' => $row->{'home_address_2'}),
            _opt('city'         => $row->{'home_city'}),
            _opt('region'       => $row->{'home_state'}),
            _opt('postalCode'   => $row->{'home_zip_code'}),
            _opt('countryId'    => 'US'),
        };
    }
    if (_has_any($row, qw(dorm_room dorm_address dorm_city dorm_state dorm_zip_code))) {
        my %defaults = (
            'dorm_address'  => '255 Brookline Avenue',
            'dorm_city'     => 'Boston',
            'dorm_state'    => 'MA',
            'dorm_zip_code' => '02215',
            'countryId'     => 'US',
        );
        push @addresses, {
            %defaults,
            # _req('id'           => $self->_uuid),
            _req('addressTypeId' => $campus),
            _opt('addressLine1' => $row->{'dorm_room'}),
            _opt('addressLine2' => $row->{'dorm_address'}),
            _opt('city'         => $row->{'dorm_city'}),
            _opt('region'       => $row->{'dorm_state'}),
            _opt('postalCode'   => $row->{'dorm_zip_code'}),
        };
    }
    if (_has_any($row, qw(work_address_1 work_address_2))) {
        push @addresses, {
            # _req('id'           => $self->_uuid),
            _req('addressTypeId' => $campus),
            _opt('addressLine1' => $row->{'work_address_1'}),
            _opt('addressLine2' => $row->{'work_address_2'}),
            _opt('city'         => $row->{'work_city'} || 'Boston'),
            _opt('region'       => $row->{'work_state'} || 'MA'),
            _opt('postalCode'   => $row->{'work_zip_code'} || '02215'),
            _opt('countryId'    => 'US'),
        };
    }
    if (@addresses) {
        $addresses[0]{'primaryAddress'} = 1;
    }
	my ($id_number) = @$row{qw(id_number)};
    $user->{'externalSystemId'} = $id_number if defined $id_number;
    $user->{'patronGroup'} = $self->_patron_group($row);
    return $user;
}

# ------------------------------------------------------------------------------

package Biblio::FolioX::PatronFile::Millennium::Students;

use Biblio::FolioX::PatronFile;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile::Millennium);

BEGIN {
    *Biblio::FolioX::PatronFile::Millennium::Students::_req = *Biblio::FolioX::PatronFile::_req;
    *Biblio::FolioX::PatronFile::Millennium::Students::_opt = *Biblio::FolioX::PatronFile::_opt;
}

sub _columns {
    return [qw(
        program
        class
        id_number
        last_name
        first_name
        middle_initial
        home_address_1
        home_address_2
        home_city
        home_state
        home_zip_code
        home_phone
        dorm_room
        dorm_address
        dorm_city
        dorm_state
        dorm_zip_code
        university_phone
        email
    )];
}

sub _apply_defaults {
    my ($self, $row) = @_;
    my %def = (
        dorm_address  => '255 Brookline Avenue',
        dorm_city     => 'Boston',
        dorm_state    => 'MA',
        dorm_zip_code => '02215',
    );
    while (my ($k, $v) = each %def) {
        my $v2 = $row->{$k};
        return if defined $v2 && length $v2;
    }
    $row->{$_} = $def{$_} for keys %def;
}

sub _make_user {
    my ($self, $row) = @_;
    $self->_apply_defaults($row);
    my $user = $self->_make_generic_user($row);
    return $user;
}

sub _patron_group {
    my ($self, $row) = @_;
    my ($k1, $k2) = @$row{qw(program class)};
    $k1 =~ s/.+\.(?=OL$)//     # All *.OL programs => OL
        or
    $k1 =~ s/^PH\.D\..*/PH.D/  # All PH.D.* classes => PH.D
        ;
    my $uuidmap = $self->{'uuidmap'}{'patronGroup'}
        or die "no UUID map";
    foreach ("$k1:$k2", "$k1:*", "*:$k2", "*:*") {
        my $v = $uuidmap->{$_};
        return $v if defined $v;
    }
    die "no patron group: program=$k1, class=$k2";
}

# ------------------------------------------------------------------------------

package Biblio::FolioX::PatronFile::Millennium::Employees;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile::Millennium);

BEGIN {
    *Biblio::FolioX::PatronFile::Millennium::Employees::_req = *Biblio::FolioX::PatronFile::_req;
    *Biblio::FolioX::PatronFile::Millennium::Employees::_opt = *Biblio::FolioX::PatronFile::_opt;
}

sub _columns {
    return [qw(
        department
        affiliation
        id_number
        last_name
        first_name
        middle_initial
        work_address_1
        work_address_2
        extension
        home_address_1
        home_address_2
        home_city
        home_state
        home_zip_code
        home_phone
        email
    )];
}

sub _apply_defaults {
    my ($row);
    # There aren't any!
}

sub _make_user {
    my ($self, $row) = @_;
    $self->_apply_defaults($row);
    my $user = $self->_make_generic_user($row);
    return $user;
}

sub _patron_group {
    my ($self, $row) = @_;
    my ($k1, $k2) = @$row{qw(department affiliation)};
    my $uuidmap = $self->{'uuidmap'}
        or die "no UUID map";
    foreach ("$k1:$k2", "$k1:*", "*:$k2", "*:*") {
        my $v = $uuidmap->{'patronGroup:'.$_};
        return $v if defined $v;
    }
    die "no patron group: department=$k1, affiliation=$k2";
}

1;
