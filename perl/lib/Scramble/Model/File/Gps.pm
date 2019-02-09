package Scramble::Model::File::Gps;

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

1;
