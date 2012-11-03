package Scramble::Waypoint;

use strict;

our @ISA = qw(Scramble::XML);

sub new {
    my ($arg0, $xml) = @_;

    return bless({ %$xml }, ref($arg0) || $arg0);
}

sub new_waypoints {
    my ($id, $xmls) = @_;

    my @waypoints;
    my $last_time_waypoint; # no-time=false
    my $last_waypoint; # no-time might be false
    foreach my $waypoint_element (@$xmls) {
	my %carry_over;
	if ($waypoint_element->{'no-time'}) {
	    die "first waypoint has no time" unless $last_time_waypoint;
	    $carry_over{'start-altimeter'} = $waypoints[-1]->get_end_altimeter();
	} elsif($last_time_waypoint) {
	    if (! $last_waypoint->has_time()) {
		$carry_over{'real-start-altimeter'} = $last_waypoint->get_end_altimeter();
	    }
	    @carry_over{'start-altimeter', 'start-time', 'start-location'} = ($last_time_waypoint->get_end_altimeter(),
									      $last_time_waypoint->get_end_time(),
									      $last_time_waypoint->get_end_location());
	}
	my $waypoint = Scramble::Waypoint->new({ %carry_over, %$waypoint_element, '_id' => $id });
	push @waypoints, $waypoint;
	if ($waypoint->has_time()) {
	    $last_time_waypoint = $waypoint;
	}
	$last_waypoint = $waypoint;
    }

    return @waypoints;
}

######################################################################

sub get_end_location {$_[0]->_get_optional('end-location') }
sub get_start_location {$_[0]->_get_optional('start-location') }
sub get_end_altimeter {$_[0]->_get_optional('end-altimeter') }
sub get_start_altimeter {$_[0]->_get_optional('start-altimeter') }
sub get_real_start_altimeter {$_[0]->_get_optional('real-start-altimeter') }
sub get_type  { $_[0]->_get_optional('type') }
sub get_start_time { $_[0]->_get_optional('start-time') }
sub get_end_time { $_[0]->_get_optional('end-time') }
sub has_time { ! $_[0]->_get_optional('no-time') }

# deprecated attribute
sub get_date {  $_[0]->_get_optional('date') }

sub get_elevation_gain {
    my $self = shift;

    my $start = (defined $self->get_real_start_altimeter() 
		 ? $self->get_real_start_altimeter()
		 : $self->get_start_altimeter());
    if (defined $self->get_end_altimeter() && defined $start) {
	return $self->get_end_altimeter() - $start;
    }

    return undef;
}

sub get_minutes {
    my $self = shift;

    if ($self->get_start_time() || $self->get_end_time()) {
	return eval { Scramble::Time::delta_dates($self->get_start_time(), $self->get_end_time()) }
	    || die "Unable to delta start and end time ($@): " . Data::Dumper::Dumper($self);
    } elsif ($self->_get_optional('hours') || $self->_get_optional('minutes')) {
	# 'hours' and 'minutes' are are deprecated attributes
	return ($self->_get_optional('hours') || 0) * 60 + ($self->_get_optional('minutes') || 0);
    } else {
	return undef;
    }
}

1;
