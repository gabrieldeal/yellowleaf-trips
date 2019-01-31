package Scramble::Controller::WaypointsFragment;

use strict;

use HTML::Entities ();

sub get_short_html {
    my ($waypoints) = @_;

    my $delta = $waypoints->get_car_to_car_delta();
    return '' unless $delta;
    return Scramble::Time::format_time(0, $delta);
}

sub get_detailed_params {
    my ($waypoints) = @_;

    my @waypoints = $waypoints->get_waypoints_with_times();
    return '' unless @waypoints;

    my @waypoint_params;
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
        push @waypoint_params, {
            time_html => Scramble::Time::format_time(0, $delta),
            type => $type,
            from_location_html => Scramble::Htmlify::insert_links($w1->get_location),
            to_location_html => Scramble::Htmlify::insert_links($w2->get_location),
        };
    }

    return {
        summary_time_html => get_short_html($waypoints),
        detailed_times => \@waypoint_params,
    };
}

1;
