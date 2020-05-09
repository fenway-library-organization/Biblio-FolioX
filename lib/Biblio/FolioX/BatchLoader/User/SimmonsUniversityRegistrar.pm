package Biblio::FolioX::BatchLoader::User::SimmonsUniversityRegistrar;

use strict;
use warnings;

use Biblio::Folio::Site::BatchLoader;

use vars qw(@ISA);
@ISA = qw(Biblio::Folio::Site::BatchLoader);

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

1;
