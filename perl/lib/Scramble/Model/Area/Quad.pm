package Scramble::Model::Area::Quad;

use strict;

use Scramble::Model::Area ();

our @ISA = qw(Scramble::Model::Area);

sub new {
    my $arg0 = shift;
    my ($self) = @_;

    my $short_name = $self->get_name();

    $self->{'name'} = $short_name . " USGS quad";
    $self->{'short-name'} = $short_name;
    bless($self, ref($arg0) || $arg0);

    $self->_set_required(qw(short-name));

    return $self;
}

sub get_short_name { $_[0]->{'short-name'} }
sub get_neighboring_quad_id { $_[0]->_get_optional($_[1]) }

1;
