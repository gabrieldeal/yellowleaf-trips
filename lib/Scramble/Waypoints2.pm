package Scramble::Waypoints2;

use strict;

use Scramble::Waypoint2 ();

our @ISA = qw(Scramble::XML);

my $gOnTrailTypeRegexes = 'ascending|descending|traversing|hiking|jogging';

sub new {
    my $arg0 = shift;
    my ($id, $xml) = @_;

    $xml ||= {};
    my $self = bless({ %$xml, '_id' => $id }, ref($arg0) || $arg0);

    my $waypoints = $self->_get_optional('waypoint') || [];

    my @waypoints;
    foreach my $point_xml (@$waypoints) {
	push @waypoints, Scramble::Waypoint2->new($point_xml);
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

sub get_locations_visited {
    my $self = shift;

    my @locations_visited;
    foreach my $waypoint ($self->get_waypoints()) {
	push @locations_visited, Scramble::Location::get_locations_referenced($waypoint->get_location());
    }

    return Scramble::Misc::dedup(@locations_visited);
}

sub get_elevation_gain {
    my $self = shift;

    my $gain = $self->_get_optional("elevation-gain");
    if (defined $gain) {
        return undef if $gain == 0;
        return Scramble::Misc::format_elevation($gain);
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
    return Scramble::Misc::format_elevation($gain);
}

sub get_car_to_car_delta {
    my $self = shift;

    my $car_to_car_hours = $self->_get_optional('car-to-car-hours');
    if (defined $car_to_car_hours) {
        return 60*$car_to_car_hours;
    }

    my @waypoints = $self->get_on_trail_waypoints();
    return '' unless @waypoints;

    my $minutes = Scramble::Time::delta_dates($waypoints[0]->get_time(), 
                 	                      $waypoints[$#waypoints]->get_time());
    if ($minutes < 24*60) {
        return $minutes;
    }

    my $start_day = Scramble::Time::get_days_since_1BC($waypoints[0]->get_time());
    my $end_day = Scramble::Time::get_days_since_1BC($waypoints[$#waypoints]->get_time());
    return ($end_day - $start_day + 1) * 24 * 60;
}

sub get_car_to_car_html {
    my $self = shift;

    my $delta = $self->get_car_to_car_delta();
    return '' unless $delta;

   Scramble::Misc::make_colon_line("Car-to-car time",
                                     Scramble::Time::format_time(0, $delta));
}

sub get_detailed_time_html {
    my $self = shift;

    my @waypoints = $self->get_waypoints_with_times();
    return '' unless @waypoints;

    my @waypoint_htmls;
    my @summaries;

    for (my $i = 1; $i < @waypoints; ++$i) {
	my $w1 = $waypoints[$i-1];
	my $w2 = $waypoints[$i];
	my $type = $w1->get_type();
	next if $type eq 'break';

	my $delta = Scramble::Time::delta_dates($w1->get_time(), 
						$w2->get_time());
	defined $delta or die("Delta failed: ",
			      Data::Dumper::Dumper($w1),
			      Data::Dumper::Dumper($w2));
	if (@summaries && $type eq $summaries[-1]{'type'}) {
	    $summaries[-1]{'accum'} += $delta;
	} else {
	    push @summaries, { 'accum' => $delta, 
			       'type' => $type,
			   };
	}
	push @waypoint_htmls, sprintf("%s %s from %s to %s",
				      Scramble::Time::format_time(0, $delta),
				      $type,
				      Scramble::Misc::insert_links($w1->get_location()),
				      Scramble::Misc::insert_links($w2->get_location()));
    }

    my @summary_htmls;

    if ($self->get_car_to_car_delta()) {
        unshift @summary_htmls, $self->get_car_to_car_html();
    }

    my $html = "@summary_htmls";
    if (@waypoint_htmls) {
        $html .= sprintf("<ul><li>%s</li></ul>",
                         join("</li><li>", @waypoint_htmls));
    }

    return $html;
}

1;
