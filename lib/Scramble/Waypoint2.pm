package Scramble::Waypoint2;

use strict;

our @ISA = qw(Scramble::XML);

sub new {
    my $arg0 = shift;
    my ($xml) = @_;

    my $self = bless({ %$xml }, ref($arg0) || $arg0);

    my $elevation = $self->_get_optional('elevation');
    if (defined $elevation) {
print "Delete this code after migrating to the converted report XML.\n";
        my %details = Scramble::Misc::get_elevation_details($elevation);
        $self->{elevation} = $details{feet};
    }

    return $self;
}

sub get_location { $_[0]->_get_required('location') }
sub get_elevation { $_[0]->{elevation} }
sub get_type  { $_[0]->_get_required('type') }
sub get_time { $_[0]->_get_optional('time') }
sub has_time { $_[0]->get_time() ? 1 : 0 }

1;
