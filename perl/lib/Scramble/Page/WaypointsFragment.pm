package Scramble::Page::WaypointsFragment;

use strict;

use HTML::Entities ();

sub get_short {
    my ($waypoints) = @_;

    my $delta = $waypoints->get_car_to_car_delta();
    return '' unless $delta;

   Scramble::Misc::make_colon_line("Car-to-car time",
                                     Scramble::Time::format_time(0, $delta));
}

# FIXME: Refactor display code into a template.
sub get_detailed {
    my ($waypoints) = @_;

    my @waypoints = $waypoints->get_waypoints_with_times();
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

    if ($waypoints->get_car_to_car_delta()) {
        unshift @summary_htmls, get_short($waypoints);
    }

    my $html = "@summary_htmls";
    if (@waypoint_htmls) {
        $html .= sprintf("<ul><li>%s</li></ul>",
                         join("</li><li>", @waypoint_htmls));
    }

    return $html;
}

1;
