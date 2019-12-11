package Biblio::FolioX::PatronFile::Millennium;

use strict;
use warnings;

use Clone qw(clone);
use Biblio::FolioX::PatronFile;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile);

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
    my %row;
    @row{@$cols} = @row;
    return $self->_make_user(\%row);
}

sub _make_generic_user {
    my ($self, $row) = @_;
    my @addresses;
    my $user = {
        _req('id'         => $self->_uuid),
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
    my @home_address = @$row{qw(home_address_1 home_address_2 home_city home_state home_zip_code)};
    if (grep { defined($_) && length($_) } @home_address) {
        push @addresses, {
            _req('id'           => $self->_uuid),
            _opt('addressLine1' => $user->{'home_address_1'}),
            _opt('addressLine2' => $user->{'home_address_2'}),
            _opt('city'         => $user->{'home_city'}),
            _opt('region'       => $user->{'home_state'}),
            _opt('postalCode'   => $user->{'home_zip_code'}),
            _opt('countryId'    => 'US'),
        };
    }
    my @dorm_address = @$row{qw(dorm_room dorm_address dorm_city dorm_state dorm_zip_code)};
    if (grep { defined($_) && length($_) } @dorm_address) {
        my %defaults = (
            'dorm_address'  => '255 Brookline Avenue',
            'dorm_city'     => 'Boston',
            'dorm_state'    => 'MA',
            'dorm_zip_code' => '02215',
            'countryId'     => 'US',
        );
        push @addresses, {
            %defaults,
            _req('id'           => $self->_uuid),
            _opt('addressLine1' => $user->{'dorm_room'}),
            _opt('addressLine2' => $user->{'dorm_address'}),
            _opt('city'         => $user->{'dorm_city'}),
            _opt('region'       => $user->{'dorm_state'}),
            _opt('postalCode'   => $user->{'dorm_zip_code'}),
        };
    }
    return $user;
}

# ------------------------------------------------------------------------------

package Biblio::FolioX::PatronFile::Millennium::Students;

use Biblio::FolioX::PatronFile;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile::Millennium);

BEGIN {
    *_req = *Biblio::FolioX::PatronFile::_req;
    *_opt = *Biblio::FolioX::PatronFile::_opt;
}

sub _columns {
    return [qw(
        acad_program
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
        dorm_address  => '255_Brookline_Avenue',
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
    my @addresses;
    my $user = $self->_make_generic_user($row);
    return $user;
}

# ------------------------------------------------------------------------------

package Biblio::FolioX::PatronFile::Millennium::Employees;

use vars qw(@ISA);
@ISA = qw(Biblio::FolioX::PatronFile::Millennium);

BEGIN {
    *_req = *Biblio::FolioX::PatronFile::_req;
    *_opt = *Biblio::FolioX::PatronFile::_opt;
}

sub _columns {
    return [qw(
        department
        position_class
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
    my $user = $self->_default_user;
    my $personal = $user->{'personal'} ||= {};
    my $addresses = $personal->{'addresses'} ||= [];
    my @home_address = @$row{qw(home_address_1 home_address_2 home_city home_state home_zip_code)};
    if (grep { defined($_) && length($_) } @home_address) {
        push @$addresses, {
            _req('id'           => $self->_uuid),
            _opt('addressLine1' => $row->{'home_address_1'}),
            _opt('addressLine2' => $row->{'home_address_2'}),
            _opt('city'         => $row->{'home_city'}),
            _opt('region'       => $row->{'home_state'}),
            _opt('postalCode'   => $row->{'home_zip_code'}),
        };
    }
    return $user;
}

1;
