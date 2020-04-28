package Biblio::FolioX::BatchLoader::User::SimmonsUniversityRegistrar;

use strict;
use warnings;

use Biblio::Folio::Site::BatchLoader;

use vars qw(@ISA);
@ISA = qw(Biblio::Folio::Site::BatchLoader);

sub prepare_one {
    my ($self, $item) = @_;
    my ($record, $matches) = @$item{qw(record matches)};
    my $profile = $self->profile;
    my $actions = $profile->{'actions'};
    # See if there is exactly one suitable match
    my ($one_match, $action);
    my $rpg = $record->{'patronGroup'};
    my @pg_matches = grep { $_->{'object'}{'patronGroup'} eq $rpg } @$matches;
    if (@$matches == 0) {
        # No matches at all
        $action = $actions->{'noMatch'} || 'create';
    }
    elsif (@pg_matches == 1) {
        # One match with the right patronGroup
        $action = $actions->{'oneMatch'} || 'update';
        $one_match = $pg_matches[0]{'object'};
    }
    elsif (@pg_matches > 1) {
        # Too many matches
        $action = $actions->{'multipleMatches'} || 'skip';
        $item->{'warning'} = "too many matches:";
    }
    elsif (@$matches == 1) {
        # One match, even though the patronGroup is different
        $one_match = $matches->[0]{'object'};
        $action = $actions->{'oneMatch'} || 'update';
    }
    $item->{'action'} = $action;
    $item->{'object'} = $one_match;
    if (!defined $one_match && $action eq 'create') {
        $self->_prepare_create($item);
    }
    elsif ($action eq 'update') {
        $self->_prepare_update($item);
    }
    elsif ($action eq 'delete') {
        $self->_prepare_delete($item)
    }
    else {
        return;
    }
    return $item;
}

sub _prepare_create {
    my ($self, $item) = @_;
    $item->{'object'}{'id'} = $self->site->folio->uuid;
}

sub _prepare_update {
    my ($self, $item) = @_;
    my ($object, $record) = @$item{qw(object record)};
    # Update $object from $record
    my @oaddr = sort {
        0
    } @{ $object->{'personal'}{'addresses'} };
    $object->{'personal'}{'addresses'} = \@oaddr;
    my %update;
    $item->{'update'} = \%update;
}

sub _prepare_delete { }

1;
