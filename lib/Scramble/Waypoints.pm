package Scramble::Waypoints;

use strict;

use Scramble::XML ();
use Scramble::Waypoint ();
use Scramble::Time ();

our @ISA = qw(Scramble::XML);

sub new {
    my ($arg0, $id, $xml) = @_;

    my $self =  bless({ %$xml, '_id' => $id }, ref($arg0) || $arg0);

    $self->{'waypoints'} = [ Scramble::Waypoint::new_waypoints($id, $self->_get_optional('time')) ];

    return $self;
}

sub get_id { $_[0]->{'_id'} }
sub get_waypoints { @{ $_[0]->{'waypoints'} }}
sub get_waypoints_with_times { grep { $_->has_time() } $_[0]->get_waypoints() }

sub get_locations_visited {
    my $self = shift;

    my @locations_visited;
    foreach my $waypoint ($self->get_waypoints()) {
	foreach my $location_method (qw(get_start_location get_end_location)) {
	    my $location_description = $waypoint->$location_method();
	    next unless defined $location_description;
	    push @locations_visited, Scramble::Location::get_locations_referenced($location_description);
	}
    }

    return Scramble::Misc::dedup(@locations_visited);
}

sub get_elevation_gain {
    my $self = shift;
    my ($time_type) = @_;

    return undef unless $self->get_waypoints();

    my $total_gain = 0;
    my $found_match = 0;
    foreach my $waypoint ($self->get_waypoints()) {
	die "No type: " . Data::Dumper::Dumper($waypoint) unless defined $waypoint->get_type();
	next unless $waypoint->get_type() =~ /$time_type/;
	$found_match = 1;
	my $gain = $waypoint->get_elevation_gain();
	if (! defined $gain) {
	    return undef;
	}
	if ($gain > 0) {
	    $total_gain += $gain;
	}
    }

    return ($found_match
	    ? Scramble::Misc::format_elevation($total_gain) 
	    : undef);
}

sub get_start_to_end_time {
    my $self = shift;

    # eliminate old-style reports with <time> elements that don't have
    # start and end times.
    my @waypoints = $self->get_waypoints_with_times();
    if (! @waypoints || ! defined $waypoints[0]->get_start_time()) {
	return undef;
    }

    my ($first_time, $last_time, $prev_date);
    foreach my $waypoint (@waypoints) {
	next unless $waypoint->get_type() =~ /ascending|descending/;

	if (! defined $first_time) {
	    $first_time = $waypoint->get_start_time() || die "Missing start-time";
	}
	$last_time = $waypoint->get_end_time() || die "Missing end-time";
    }

    return undef unless defined $first_time;

    return Scramble::Time::delta_dates($first_time, $last_time);
}

sub get_yyyymmdd {
    my ($time) = @_;

    return Date::Manip::UnixDate($time, "%Y/%m/%d");
}

sub get_detailed_time_html {
    my ($self) = @_;

    my $html;
    my $prev_waypoint;
    my $prev_date;
    foreach my $waypoint ($self->get_waypoints_with_times()) {
	next unless $waypoint->has_time();

        my $type = '';
        if ($waypoint->get_type()) {
	    $type = sprintf(" <b>%s</b> ", $waypoint->get_type());
        } else {
	    printf("No type in waypoint for '%s'\n", $self->get_id());
	}

	my $date = "";
	if (defined $waypoint->get_date()) {
	    $date = $waypoint->get_date();
	}
	if ($waypoint->get_start_time() && get_yyyymmdd($waypoint->get_start_time())) {
	    $date = get_yyyymmdd($waypoint->get_start_time());
	}
	if ($date && (! $prev_date || $date ne $prev_date)) {
	    $prev_date = $date;
	    $date = "$date: " if length $date;
	} else {
	    $date = '';
	}

	my $start_location = $waypoint->get_start_location();
	my $start_altitude = $waypoint->get_start_altimeter();
	$start_location = Scramble::Misc::htmlify($start_location);
	$start_altitude = Scramble::Misc::make_optional_line(" (%s) ",
							     \&Scramble::Misc::format_elevation_short,
							     $start_altitude);

	my $end_location = Scramble::Misc::htmlify($waypoint->get_end_location()
				   || die "Missing end location: " . Data::Dumper::Dumper($waypoint));
	my $end_altitude = ($waypoint->get_end_altimeter() 
			    ? " (" . Scramble::Misc::format_elevation_short($waypoint->get_end_altimeter()) . ") "
			    : '');

        $html .= ("<li>$date" 
		  . Scramble::Time::format_time(0, $waypoint->get_minutes()) 
		  . " $type from $start_location to $end_location</li>\n");
    }

    if (defined $html) {
	$html = "<br>Altitudes below are readings from my altimeter so they are only approximate. <ul>$html</ul>";
    }

    my $total_time = $self->get_detailed_time_summary_html() || '';
    if (! defined $total_time) {
	return $html;
    } elsif (defined $html) {
	return "$total_time$html";
    } else {
	return undef;
    }
}

sub get_car_to_car_html {
    my $self = shift;

    my $html;
    if ($self->_get_optional('up-hours') || $self->_get_optional('up-minutes')) {
	return sprintf("<b>Time spent ascending:</b> %s<br>"
		       . "<b>Time spent descending:</b> %s<br>",
		       Scramble::Time::format_time($self->_get_optional('up-hours'),
				   $self->_get_optional('up-minutes')),
		       Scramble::Time::format_time($self->_get_optional('down-hours'), 
				   $self->_get_optional('down-minutes')));
    } 

    my $fmt = "<b>Total Time:</b> %s<br>";
    if ($self->_get_optional('trail-total-hours')
	|| $self->_get_optional('trail-total-hours')) 
    {
	return sprintf($fmt, Scramble::Time::format_time($self->_get_optional('trail-total-hours'), 
                                         $self->_get_optional('trail-total-hours')));
    }

    my $time = $self->get_start_to_end_time();
    if (defined $time) {
	return sprintf($fmt, Scramble::Time::format_time(0, $time));
    }

    return '';
}

sub get_detailed_time_summary_html_for_type {
    my ($self, $time_type) = @_;

    my $accum_minutes = 0;

    foreach my $waypoint ($self->get_waypoints_with_times()) {
	next unless $waypoint->get_type() =~ /$time_type/;
	$accum_minutes += $waypoint->get_minutes();
    }

    if ($accum_minutes == 0) {
	return undef;
    }

    return Scramble::Time::format_time(0, $accum_minutes);
}

sub get_detailed_time_summary_html {
    my $self = shift;

    my $html;

    my $total_time = $self->get_start_to_end_time();
    if ($total_time) {
	$html .= Scramble::Misc::make_colon_line("Total time on trail including breaks",
						 Scramble::Time::format_time(0, $total_time));
	$html .= "<br>";
    }

    foreach my $type ($self->get_time_types()) {
        my $extra = ($type =~ /ascending|descending/ ? " (not including breaks)" : '');
	$html .= sprintf("<b>%s time$extra:</b> %s<br>",
			 ucfirst($type),
			 $self->get_detailed_time_summary_html_for_type("^$type\$"));
    }
    if (defined $html) {
	return $html;
    }

    return $self->get_car_to_car_html();
}

sub get_time_types {
    my ($self) = @_;

    my @types;
    foreach my $waypoint ($self->get_waypoints_with_times()) {
	push @types, $waypoint->get_type() unless grep { $_ eq $waypoint->get_type() } @types;
    }
    return @types;
}

######################################################################
# statics
######################################################################

sub calculate_minutes {
    my ($h, $m) = @_;

    return ($h || 0) * 60 + ($m || 0);
}

######################################################################

1;
