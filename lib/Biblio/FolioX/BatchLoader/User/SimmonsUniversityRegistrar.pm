package Biblio::FolioX::BatchLoader::User::SimmonsUniversityRegistrar;

use strict;
use warnings;

use Biblio::Folio::Site::BatchLoader;

use vars qw(@ISA);
@ISA = qw(Biblio::Folio::Site::BatchLoader);

sub _prepare_update {
    my ($self, $member) = @_;
    my ($object, $record) = @$member{qw(object record)};
    # Update $object from $record
    my %oaddr = map { $_->{'addressTypeId'} => $_ } @{ $object->{'personal'}{'addresses'} };
    my %raddr = map { $_->{'addressTypeId'} => $_ } @{ $record->{'personal'}{'addresses'} };

    my @oaddr = sort { xxx } values %oaddr;
    $object->{'personal'}{'addresses'} = \@oaddr;
    my %update;
    $member->{'update'} = \%update;
}

1;
