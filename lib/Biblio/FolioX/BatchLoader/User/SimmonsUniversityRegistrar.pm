package Biblio::FolioX::BatchLoader::User::SimmonsUniversityRegistrar;

use strict;
use warnings;

use Biblio::Folio::Site::BatchLoader;
use Biblio::Folio::Util qw(_unique _unbless);

use vars qw(@ISA);
@ISA = qw(Biblio::Folio::Site::BatchLoader);

my %other_address_type = (
    '_regexp' => qr/./,
    '_order' => 9,
    '_category' => 'other',
    '_protect' => 1,
);
my @address_type_config = (
    {
        '_regexp' => qr/(?i)home/,
        '_order' => 0,
        '_category' => 'home',
        '_protect' => 0,
    },
    {
        '_regexp' => qr/(?i)campus/i,
        '_order' => 1,
        '_category' => 'campus',
        '_protect' => 0,
    },
    {
        '_regexp' => qr/(?i)slis\s*west/,
        '_order' => 2,
        '_category' => 'slis-west',
        '_protect' => 1,
    },
    {
        '_regexp' => qr/(?i)distance|online/,
        '_order' => 3,
        '_category' => 'distance',
        '_protect' => 1,
    },
    \%other_address_type,
);
my %address_type = (
    map { $_->{'_category'} => $_ } @address_type_config
);
my %address_type_order = (
    map { $_->{'_category'} => $_->{'_order'} } @address_type_config
);
my %contact_type_id = (
    'Mail' => '001',
    'Email' => '002',
    'Text message' => '003',
    'Phone' => '004',
    'Mobile phone' => '005',
);

sub init {
    my ($self) = @_;
    $self->SUPER::init;
    $self->_init_address_types
}

sub _init_address_types {
    my ($self) = @_;
    my $site = $self->site;
    # Set up address ordering by type
    my @address_types = $site->address_types;
    my %atype = %address_type;
    my %aorder = %address_type_order;
    #my @more_address_type_config;
    foreach my $atype (@address_types) {
        my $id = $atype->{'id'};
        my $code = $atype->{'addressType'};
        $atype->{'_code'} = $code;
        my ($order, $category, $protect);
        # Updatable addresses
        # TODO Put this in a config file
        my $found;
        foreach my $aconf (@address_type_config) {
            my $rx = $aconf->{'_regexp'};
            if ($rx && $code =~ $rx) {
                $found = 1;
                $atype{$code} = $atype{$id} = $aconf;
                $aorder{$code} = $aorder{$id} = $aconf->{'_order'};
                last;
            }
        }
        #push @more_address_type_config, {
        #    %$atype,
        #    '_order' => 9,
        #    '_category' => 'other',
        #} if !$found;
    }
    #push @address_type_config, @more_address_type_config;
    $self->{'_address_types'} = \%atype;
    $self->{'_address_type_order'} = \%aorder;
}

sub _sort_addresses {
    my $self = shift;
    my $aorder = $self->{'_address_type_order'};
    return sort { $aorder->{$a->{'addressTypeId'}} <=> $aorder->{$b->{'addressTypeId'}} } @_;
}

sub _prepare_create {
    my ($self, $member) = @_;
    my $record = $member->{'create'} = _unbless($member->{'record'});
    my $personal = $record->{'personal'};
    my @addresses = @{ $personal->{'addresses'} || [] };
    $personal->{'addresses'} = [ $self->_sort_addresses(@addresses) ];
    if (defined $personal->{'email'} && $personal->{'email'} =~ /[@]/) {
        $personal->{'preferredContactTypeId'} = $contact_type_id{'Email'};
    }
    else {
        $personal->{'preferredContactTypeId'} = $contact_type_id{'Mail'};
    }
}

sub _prepare_update {
    my ($self, $member) = @_;
    my ($object, $record) = @$member{qw(object record)};
    my $update = $member->{'update'} = _unbless($object);
    delete @$update{qw(createdDate updatedDate meta proxyFor)};  # Deprecated fields
    $member->{'changes'} = [];
    # Update $update from $record
    $self->_update_fields(
        'member' => $member,
        'source' => $record,
        'destination' => $update,
        'recurse' => {
            'personal' => 0,
        },
    );
    $self->_prepare_update_personal($member);
}

sub _prefix {
    # Make sure the prefix is the empty string or ends in '.'
    local $_ = shift;
    return '' if !defined || !length;
    s/\.?$/./;
    return $_;
}
    
sub _update_fields {
    my ($self, %arg) = @_;
    my ($member, $source, $destination, $recurse) = @arg{qw(member source destination recurse)};
    my ($update, $record, $changes) = @$member{qw(update record changes)};
    my $pfx = _prefix($arg{'prefix'});
    foreach my $k (_unique(keys %$source, keys %$destination)) {
        next if $k =~ /^_/;  # Don't copy private (ephemeral) fields
        my $sval = $source->{$k};
        my $dval = $destination->{$k};
        my $sref = ref $sval;
        my $dref = ref $dval;
        if ($dref eq 'HASH') {
            next if !$recurse;
            next if exists($recurse->{$k}) ? !$recurse->{$k} : !$recurse->{'*'};
            $self->_update_fields(
                'member' => $member,
                'source' => $sval,
                'destination' => $dval,
                'prefix' => $pfx.$k
            );
        }
        elsif ($dref eq 'ARRAY') {
            next if !$recurse;
            # ???
        }
        elsif (!defined $sval) {
            # Nothing to do
        }
        elsif (!defined $dval) {
            if ($sval ne '') {
                push @$changes, ['set', $pfx.$k, $sval];
                $destination->{$k} = $sval;
            }
        }
        elsif ($sval eq '' && $dval ne '') {
            push @$changes, ['unset', $pfx.$k, $dval];
            $destination->{$k} = $sval;
        }
        elsif ($dval ne $sval) {
            push @$changes, ['change', $pfx.$k, $dval, $sval];
            $destination->{$k} = $sval;
        }
    }
}

sub _prepare_update_personal {
    my ($self, $member) = @_;
    my ($update, $record, $changes) = @$member{qw(update record changes)};
    $self->_update_fields(
        'member' => $member,
        'source' => $record->{'personal'},
        'destination' => $update->{'personal'},
        'prefix' => 'personal',
        'recurse' => {
            'addresses' => 0,
        },
    );
    $self->_prepare_update_addresses($member);
}

sub _prepare_update_addresses {
    my ($self, $member) = @_;
    my ($update, $record, $changes) = @$member{qw(update record changes)};
    # Add ephemeral elements (_code, _category, _order, etc.) to each address
    my $atypes = $self->{'_address_types'};
    my $aorder = $self->{'_address_type_order'};
    my @daddr = @{ $update->{'personal'}{'addresses'} ||= [] };
    my @saddr = @{ $record->{'personal'}{'addresses'} ||= [] };
    foreach my $addr (@daddr, @saddr) {
        my $id = $addr->{'addressTypeId'};
        my $atype = $atypes->{$id} || { %other_address_type };
        my @akeys = keys %$atype;
        @$addr{@akeys} = @$atype{@akeys};
    }
    my %daddr = map { $_->{'addressTypeId'} => $_ } @daddr;
    my %saddr = map { $_->{'addressTypeId'} => $_ } @saddr;
    my @all_address_type_ids = _unique(keys %daddr, keys %saddr);
    my @daddr_new;
    foreach my $ati (@all_address_type_ids) {
        my $atype = $atypes->{$ati};
        my $atc = $self->site->address_type($ati)->_code;
        #my $atc = $atype->{'_code'} || $atype->{'addressType'};
        my $pfx = qq{personal.addresses[$atc]};
        my $daddr = $daddr{$ati};
        my $saddr = $saddr{$ati};
        if ($daddr && !$saddr) {
            # Address in the existing user in FOLIO is of a type not found in the patron file being loaded
            push @daddr_new, $daddr;
            push @$changes, ['keep', $pfx.scalar(@daddr_new)];
        }
        elsif ($saddr && !$daddr) {
            # Address in the patron file being loaded is of a type not found in the existing user in FOLIO
            push @daddr_new, $saddr;
            push @$changes, ['add', $pfx.scalar(@daddr_new)];
        }
        elsif ($saddr && $daddr) {
            # The address type is found in both -- the record being loaded "wins"
            # unless the address type is designated "protected" in the load profile
            if ($daddr->{'_protect'}) {
                push @$changes, ['protected', $pfx.scalar(@daddr_new)];
            }
            else {
                #my $i = scalar @$changes;
                $self->_update_fields(
                    'member' => $member,
                    'source' => $saddr,
                    'destination' => $daddr,
                    'prefix' => $pfx,
                );
                push @daddr_new, $daddr;
                #if (scalar @$changes > $i) {
                #    splice @$changes, $i, 0, ['update', $pfx];
                #}
            }
        }
        1;
    }
    @daddr_new = sort { $a->{'_order'} <=> $b->{'_order'} } @daddr_new;
    foreach my $addr (@daddr_new) {
        my @k = grep { /^_/ } keys %$addr;
        delete @$addr{@k};
    }
    $update->{'personal'}{'addresses'} = \@daddr_new;
}

1;
