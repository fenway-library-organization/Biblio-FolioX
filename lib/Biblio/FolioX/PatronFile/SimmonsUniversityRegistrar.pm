package Biblio::FolioX::PatronFile::SimmonsUniversityRegistrar;

use strict;
use warnings;

use Biblio::Folio::Util qw(_req _opt _str2hash _bool _utc_datetime _debug);
use Biblio::Folio::Object;
use Biblio::Folio::Site::BatchFile;

use POSIX qw(strftime);
use Clone qw(clone);
use JSON;

use vars qw(@ISA);
@ISA = qw(Biblio::Folio::Site::BatchFile);

my @address_types = qw(Home Campus);  # SLIS West is special
my @address_parts = qw(addressLine1 addressLine2 city region postalCode);
my @personal_parts = qw(firstName middleName lastName email phone mobilePhone);

sub new {
    my $cls = shift;
    unshift @_, 'file' if @_ % 2;
    my %arg = @_;
    my $file = $arg{'file'} // die "no file to parse";
    if ($file =~ /employee/i) {
        $cls .= '::Employees';
    }
    else {
        print STDERR "warning: unrecognized file name, assumed to be a student load: $file\n"
            if $file !~ /student/i;
        $cls .= '::Students';
    }
    my $self = bless { @_ }, $cls;
    $self->init;
    return $self;
}

sub site { @_ > 1 ? $_[0]{'site'} = $_[1] : $_[0]{'site'} }

sub init {
    my ($self) = @_;
    my $ug = Data::UUID->new;
    $self->{'uuidgen'} = sub {
        return $ug->create_str;
    };
    my $site = $self->site;
    $self->{'address_types'} = { map { $_->{'addressType'} => $_ } $site->address_types };
    $self->{'patron_groups'} = { map { $_->{'group'} => $_ } $site->groups };
    my $t0 = time;
    $self->{'today'} = _utc_datetime(gmtime($t0));
    $self->{'default_expiration_date'} = _utc_datetime(gmtime($t0+86400*30));
    # $self->{'uuidmap'} = $site->{'uuidmap'};
    return $self;
}

sub address_type_id {
    my ($self, $type) = @_;
    return $self->{'address_types'}{$type}{'id'};
}

sub patron_group_id {
    my ($self, $group) = @_;
    return $self->{'patron_groups'}{$group}{'id'};
}

sub header_mapping {
    return _str2hash(q{
        First_Name              personal.firstName
        Middle_Name             personal.middleName
        Last_Name               personal.lastName
        Email_Address           personal.email
        Pref_Address_Phone      personal.phone
        Personal_Cell_Phone     personal.mobilePhone
        User_Name               username
        Simmons_Id              externalSystemId
        active                  active
        ANT_CMPL_Date           expirationDate
        Patron_Group            patronGroup
        Pref_Address_Line_1     homeAddress.addressLine1
        Pref_Address_Line_2     homeAddress.addressLine2
        Pref_City               homeAddress.city
        Pref_ST                 homeAddress.region
        Pref_Zip                homeAddress.postalCode
        Dorm_Room               campusAddress.addressLine1.0.Room
        Dorm_BLDG               campusAddress.addressLine1.1.Building
        Dorm_Address_Line1      campusAddress.addressLine1.2.Remainder
        Dorm_Addressv_Line2     campusAddress.addressLine2
        Dorm_City               campusAddress.city
        Dorm_State              campusAddress.region
        Dorm_Zip                campusAddress.postalCode
        Start_Date              enrollmentDate
        # Fields to ignore:
		Personal_Address_Type   -
		Dorm_Address			-
        # Old field names:
        # V.FIRST.NAME        first_name
        # V.LAST.NAME         last_name
        # V.MIDDLE.NAME[1,1]  middle_initial
        # V.MIDDLE.NAME       middle_initial
        # X.ADDRESS.PHONE     home_phone
    });
}

sub columns {
    my ($self, $cols) = @_;
    return @{ $self->{'columns'} = $cols } if $cols;
    return @{ $self->{'columns'} || [] };
}

sub next {
    my ($self, $fh) = @_;
    my @cols = $self->columns;
    my ($line, @row);
    while (1) {
        $line = <$fh>;
        $self->{'eof'} = 1, return if !defined $line;
        chomp $line;
        $line =~ s/\r$//;
        @row = split /\|/, $line;
        last if @cols;
        @cols = $self->set_header(@row);
    }
    my $n = @cols;
    push @row, '' while @row < $n;
    while (@row > $n) {
        die "data in extra column"
            if $row[-1] ne '';
        pop @row;
    }
    my %row = (
        '_raw' => $line,
        '_lno' => $.,
    );
    @row{@cols} = @row;
	delete $row{'-'};  # Any ignored fields
    my $l = $. - 2;
    _debug("[$l] username=$row{username} <= $line");
    return $self->make_user(\%row);
}

sub set_header {
    my ($self, @header) = @_;
    my $file = $self->file;
    my %map = $self->header_mapping;
    my @mapped_header = map {
        $map{$_} // die "unrecognized field label in header for file $file: $_"
    } @header;
    $self->{'unmapped_columns'} = \@header;
    return @{ $self->{'columns'} = \@mapped_header };
}

sub make_user {
    my ($self, $row) = @_;
    _debug('>> ' . __PACKAGE__ . '::make_user(username=' . $row->{'username'} . ')');
    $self->apply_defaults($row);
    my $personal = $self->make_personal($row);
    my $user = {
        # _req('id'         => _uuid),
        _req('_raw'    => $row->{'_raw'}),
        _req('_parsed' => $row),
		_req('active' 		    => _bool($row->{'active'})),
        _req('patronGroup'      => $self->patron_group_id($row->{'patronGroup'})),
        _req('personal'         => $personal),
        _opt('externalSystemId' => $row->{'externalSystemId'}),
        _opt('username'         => $row->{'username'}),
        _opt('enrollmentDate'   => _datetime($row->{'enrollmentDate'}, $self->{'today'})),
        _opt('expirationDate'   => _datetime($row->{'expirationDate'}, $self->{'default_expiration_date'})),
    };
    _debug('<< ' . __PACKAGE__ . '::make_user(username=' . $user->{'username'} . ')');
    return $user;
}

sub _datetime {
    my ($str, $default) = @_;
    return $default if !defined $str;
    return _utc_datetime("$3-$1-$2") if $str =~ m{^([0-9]{2})[-/_]([0-9]{2})[-/_]([0-9]{4})$};
    return _utc_datetime($str) if $str =~ m{^([0-9]{4})[-/_]?([0-9]{2})[-/_]?([0-9]{2})(?:$|T)};
    return $default if defined $default;
    _debug("bad date/time: $str");
    die "bad date/time: $str";
}

sub apply_defaults {
    # Nothing special to do
}

sub make_personal {
    my ($self, $row) = @_;
    my @addresses;
    my $personal = {
        (map { _opt($_ => $row->{"personal.$_"}) } @personal_parts),
        _opt('dateOfBirth' => undef),
        _req('addresses'  => \@addresses),
    };
    if (!$personal->{'lastName'}) {
        # TODO complain or die?
        $personal->{'lastName'} = '[none]';
    }
    @addresses = grep { defined }
                 map { $self->make_address($_, $row) } @address_types;
    $addresses[0]{'primaryAddress'} = JSON::true if @addresses;
    delete $personal->{''};
    return $personal;
}

sub make_address {
    my ($self, $type, $row) = @_;
    my %addr;
    my $empty = 1;
    foreach my $part (@address_parts) {
        my $key = lc($type) . 'Address.' . $part;
        my @subkeys = grep { /^$key\..+$/ } keys %$row;
        my $val = $row->{$key};
        if (@subkeys) {
            print STDERR "warning: $type address has both key $key and subkeys ", join(', ', @subkeys), "\n"
                if defined $val;
            my @vals = @$row{sort @subkeys};
            $val = join(' ', grep { defined } $val, @vals);
        }
        if (defined $val) {
            $empty = 0 if $val =~ /\S/;
            $addr{$part} = $val;
        }
    }
    return if $empty;
    $addr{'addressTypeId'} = $self->address_type_id($type);
    return \%addr;
}

#    if (_has_any($row, qw(home_address_1 home_address_2 home_city home_state home_zip_code))) {
#        # Home address
#        push @addresses, {
#            # _req('id'           => _uuid),
#            _req('addressTypeId' => $home),
#            _opt('addressLine1' => $row->{'home_address_1'}),
#            _opt('addressLine2' => $row->{'home_address_2'}),
#            _opt('city'         => $row->{'home_city'}),
#            _opt('region'       => $row->{'home_state'}),
#            _opt('postalCode'   => $row->{'home_zip_code'}),
#            _opt('countryId'    => 'US'),
#        };
#    }
#    if (_has_any($row, qw(dorm_room dorm_address dorm_city dorm_state dorm_zip_code))) {
#        my %defaults = (
#            'dorm_address'  => '255 Brookline Avenue',
#            'dorm_city'     => 'Boston',
#            'dorm_state'    => 'MA',
#            'dorm_zip_code' => '02215',
#            'countryId'     => 'US',
#        );
#        push @addresses, {
#            %defaults,
#            # _req('id'           => _uuid),
#            _req('addressTypeId' => $campus),
#            _opt('addressLine1' => $row->{'dorm_room'}),
#            _opt('addressLine2' => $row->{'dorm_address'}),
#            _opt('city'         => $row->{'dorm_city'}),
#            _opt('region'       => $row->{'dorm_state'}),
#            _opt('postalCode'   => $row->{'dorm_zip_code'}),
#        };
#    }
#    if (_has_any($row, qw(work_address_1 work_address_2))) {
#        push @addresses, {
#            # _req('id'           => _uuid),
#            _req('addressTypeId' => $campus),
#            _opt('addressLine1' => $row->{'work_address_1'}),
#            _opt('addressLine2' => $row->{'work_address_2'}),
#            _opt('city'         => $row->{'work_city'} || 'Boston'),
#            _opt('region'       => $row->{'work_state'} || 'MA'),
#            _opt('postalCode'   => $row->{'work_zip_code'} || '02215'),
#            _opt('countryId'    => 'US'),
#        };
#    }
#
sub _has_any {
    my $row = shift;
    foreach my $val (@$row{@_}) {
        return 1 if defined $val && length $val;
    }
    return 0;
}

# ------------------------------------------------------------------------------

package Biblio::FolioX::PatronFile::SimmonsUniversityRegistrar::Students; 

#use Biblio::Folio::Site::BatchFile;
use Biblio::Folio::Util qw(_req _opt _str2hash);

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile::SimmonsUniversityRegistrar);

sub header_mapping {
    my ($self) = @_;
    return $self->SUPER::header_mapping, _str2hash(q{
        # ---------------------------------------------------------
        # Unused fields:
        # Personal_Address_Type   Preferred
        # Dorm_Address            Dorm_Address
        # ---------------------------------------------------------
        # Old field names:
        # V.STPR.ACAD.PROGRAM    program
        # V.STA.CLASS            class
        # V.ID                   id_number
        # XL.ADDRESS.LINES<1,1>  home_address_1
        # XL.ADDRESS.LINES<1,2>  home_address_2
        # X.CITY                 home_city
        # X.STATE                home_state
        # X.ZIP                  home_zip_code
        # X.RMAS.ROOM.BLDG       dorm_room
        # X.RMAS.ADDRESS         dorm_address
        # X.RMAS.CITY            dorm_city
        # X.RMAS.STATE           dorm_state
        # X.RMAS.ZIP             dorm_zip_code
        # X.PERSONAL.CELL.PHONE  university_phone
        # X.EMAIL.ADDRESS        email
    });
}

###     return [qw(
###         program
###         class
###         id_number
###         last_name
###         first_name
###         middle_initial
###         home_address_1
###         home_address_2
###         home_city
###         home_state
###         home_zip_code
###         home_phone
###         dorm_room
###         dorm_address
###         dorm_city
###         dorm_state
###         dorm_zip_code
###         university_phone
###         email
###     )];

### sub _apply_defaults {
###     my ($self, $row) = @_;
###     my %def = (
###         dorm_address  => '255 Brookline Avenue',
###         dorm_city     => 'Boston',
###         dorm_state    => 'MA',
###         dorm_zip_code => '02215',
###     );
###     while (my ($k, $v) = each %def) {
###         my $v2 = $row->{$k};
###         return if defined $v2 && length $v2;
###     }
###     $row->{$_} = $def{$_} for keys %def;
### }

### sub patron_group {
###     my ($self, $row) = @_;
###     my ($k1, $k2) = @$row{qw(program class)};
###     $k1 =~ s/.+\.(?=OL$)//     # All *.OL programs => OL
###         or
###     $k1 =~ s/^PH\.D\..*/PH.D/  # All PH.D.* classes => PH.D
###         ;
###     my $uuidmap = $self->{'uuidmap'}{'patronGroup'}
###         or die "no UUID map";
###     foreach ("$k1:$k2", "$k1:*", "*:$k2", "*:*") {
###         my $v = $uuidmap->{$_};
###         return $v if defined $v;
###     }
###     die "no patron group: program=$k1, class=$k2";
### }

# ------------------------------------------------------------------------------

package Biblio::FolioX::PatronFile::SimmonsUniversityRegistrar::Employees;

#use Biblio::Folio::Site::BatchFile;
use Biblio::Folio::Util qw(_req _opt _str2hash);

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile::SimmonsUniversityRegistrar);

sub header_mapping {
    my ($self) = @_;
    return $self->SUPER::header_mapping, _str2hash(q{
        # ---------------------------------------------------------
        # Old field names:
        # X.POS.DEPT                  department
        # X.POS.CLASS.TRANSLATION     affiliation
        # V.HRPER.ID                  id_number
        # V.BLDG.DESC                 work_address_1
        # V.HRP.PRI.CAMPUS.OFFICE     work_address_2
        # V.HRP.PRI.CAMPUS.EXTENSION  extension
        # VL.ADDRESS.LINES<1,1>       home_address_1
        # VL.ADDRESS.LINES<1,2>       home_address_2
        # V.CITY                      home_city
        # V.STATE                     home_state
        # V.ZIP                       home_zip_code
        # X.SIMMONS.EMAIL.ADDRESS     email
    });
}

###     return [qw(
###         department
###         affiliation
###         id_number
###         last_name
###         first_name
###         middle_initial
###         work_address_1
###         work_address_2
###         extension
###         home_address_1
###         home_address_2
###         home_city
###         home_state
###         home_zip_code
###         home_phone
###         email
###     )];

### sub _apply_defaults {
###     my ($row);
###     # There aren't any!
### }

### sub patron_group {
###     my ($self, $row) = @_;
###     my ($k1, $k2) = @$row{qw(department affiliation)};
###     my $uuidmap = $self->{'uuidmap'}{'patronGroup'}
###         or die "no UUID map";
###     foreach ("$k1:$k2", "$k1:*", "*:$k2", "*:*") {
###         my $v = $uuidmap->{$_};
###         return $v if defined $v;
###     }
###     die "no patron group: department=$k1, affiliation=$k2";
### }

1;

# vim:set et ts=4 cin si:
