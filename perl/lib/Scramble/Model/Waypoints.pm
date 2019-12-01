package Scramble::Model::Waypoints;

use strict;

use Scramble::Controller::ElevationFragment ();
use Scramble::Model::Waypoint ();

our @ISA = qw(Scramble::Model);

my $gOnTrailTypeRegexes = 'ascending|descending|traversing|hiking|jogging';

sub new {
    my $arg0 = shift;
    my ($id, $xml) = @_;

    $xml ||= {};
    my $self = bless({ %$xml, '_id' => $id }, ref($arg0) || $arg0);

    my $waypoints = $self->_get_optional('waypoint') || [];

    my @waypoints;
    foreach my $point_xml (@$waypoints) {
	push @waypoints, Scramble::Model::Waypoint->new($point_xml);
    }
    $self->{'waypoints'} = \@waypoints;

    return $self;
}

sub get_id { $_[0]->{'_id'} }
sub get_waypoints { @{ $_[0]->{'waypoints'} } }
sub get_waypoints_with_times { grep { $_->has_time() } $_[0]->get_waypoints() }

sub get_on_trail_waypoints { 
    my $self = shift;

    my @waypoints = $self->get_waypoints();
    my @on_trail_waypoints;
    for (my $i = 0; $i < @waypoints; ++$i) {
	if ($waypoints[$i]->get_type() =~ /$gOnTrailTypeRegexes/i
	    || ($i > 0 && $waypoints[$i-1]->get_type() =~ /$gOnTrailTypeRegexes/i))
	{
	    push @on_trail_waypoints, $waypoints[$i];
	}
    }

    return @on_trail_waypoints;
}

# FIXME: Move the elevation-gain attribute to the <distance> element.
sub get_elevation_gain {
    my $self = shift;

    my $gain = $self->_get_optional("elevation-gain");
    if (defined $gain) {
        return undef if $gain == 0;
        return Scramble::Controller::ElevationFragment::format_elevation($gain);
    }

    my @waypoints = $self->get_on_trail_waypoints();
    return undef unless @waypoints;

    $gain = 0;
    for (my $i = 1; $i < @waypoints; ++$i) {
        if (! defined $waypoints[$i]->get_elevation()) {
            return undef;
        }
	my $diff = $waypoints[$i]->get_elevation() - $waypoints[$i-1]->get_elevation();
	if ($diff > 0) {
	    $gain += $diff;
	}
    }

    return undef if $gain == 0;
    return Scramble::Controller::ElevationFragment::format_elevation($gain);
}

sub get_car_to_car_delta {
    my $self = shift;

    my @waypoints = $self->get_on_trail_waypoints();
    return undef unless @waypoints;

    my $minutes = Scramble::Time::delta_dates($waypoints[0]->get_time(), 
                 	                      $waypoints[$#waypoints]->get_time());
    if ($minutes < 24*60) {
        return $minutes;
    }

    my $start_day = Scramble::Time::get_days_since_1BC($waypoints[0]->get_time());
    my $end_day = Scramble::Time::get_days_since_1BC($waypoints[$#waypoints]->get_time());
    return ($end_day - $start_day + 1) * 24 * 60;
}

1;
