package Scramble::Model::File::Map;

use strict;

use Scramble::Model::File ();

our @ISA = qw(Scramble::Model::File);

sub new {
    my $arg0 = shift;
    my (%args) = @_;

    my $self = { %args };
    bless $self, ref($arg0) || $arg0;

    $self->SUPER::initialize;

    return $self;
}

sub get_filenames { ($_[0]->get_filename) }
sub get_enlarged_filename { $_[0]->{'large-filename'} } # Picture-specific
sub get_enlarged_img_url { $_[0]->_get_url($_[0]->get_enlarged_filename) }

sub get_reference {
    my $self = shift;

    return {
        name => $self->get_description,
        URL => $self->get_url,
        id => 'routeMap', # used by Scramble::Model::Reference
        type => ($self->{'noroute'}
                 ? "Online map"
                 : "Online map with route drawn on it"),
    };
}

1;
