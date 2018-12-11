package Scramble::Geekery;

use strict;

sub get_list_html {
    my @htmls;
    foreach my $list_xml (Scramble::List::get_all_lists()) {
	my $climbed_count = 0;
	foreach my $list_location (@{ $list_xml->{'location'} }) {
	    my $location_object = Scramble::List::get_location_object($list_location);
	    next unless $location_object && $location_object->have_visited();
	    $climbed_count++;
	}
	next unless $climbed_count;

	my $total = @{ $list_xml->{'location'} };
        my $percent = 100 * $climbed_count / $total;
        my $html = sprintf(qq(Climbed % 6.2f%% (%d/%d) of <a href="%s">%s</a>),
                           $percent,
                           $climbed_count,
                           $total,
                           $list_xml->{'internal-URL'},
                           $list_xml->{'name'});
        $html =~ s/ /&nbsp;/; # line up the column of percentages in HTML
        $html =~ s/ /&nbsp;/;
	push @htmls, { html => $html, percent => $percent };
    }

    @htmls = reverse sort { $a->{percent} <=> $b->{percent} } @htmls;
    @htmls = map { $_->{html} } @htmls;
    return Scramble::Misc::make_optional_line("<h2>Peak Lists</h2> %s",
					      join("<br>", @htmls));
}

sub get_total_days {
  my ($stats) = @_;

  if ($stats->{'total-days'}) {
      return $stats->{'total-days'};
  }
  return '?';
}

sub nlvl {
    my ($first_choice, $second_choice) = @_;

    return defined $first_choice ? $first_choice : $second_choice;
}

sub get_stats {
    my %stats;
    foreach my $report (Scramble::Report::get_all()) {
	my $date = $report->get_start_date();
	my ($year) = ($date =~ /^(\d\d\d\d)\//);
	my $gain = $report->get_waypoints()->get_elevation_gain("ascending|descending");

        if (! exists $stats{$year}) {
            $stats{$year} = {
                             'total-days' => 0,
                             'total-trips' => 0,
                             'total-peaks' => 0,
                             'max-gain' => 0,
                             'mail-gain-per-day' => 0,
                             'estimated-gain' => 0,
                             'climbing-trips' => 0,
                             'climbing-days' => 0,
                             'trail-run-trips' => 0,
                             'trail-run-days' => 0,
                            };
        }


	my $ndays = $report->get_num_days();
	$stats{$year}{'total-days'} += $ndays;
	$stats{$year}{'total-trips'}++;
        if ($report->get_type() =~ /crag|climb|boulder/) {
            $stats{$year}{'climbing-days'} += $ndays;
            $stats{$year}{'climbing-trips'}++;
        } elsif ($report->get_type() =~ /trail run/) {
            $stats{$year}{'trail-run-days'} += $ndays;
            $stats{$year}{'trail-run-trips'}++;
        }

	my @locations = grep { $_->get_type() eq 'peak' } $report->get_location_objects();
        $stats{$year}{'total-peaks'} += @locations;

	if (! defined $stats{$year}{'max-peaks'} or $stats{$year}{'max-peaks'} < @locations) {
	    $stats{$year}{'max-peaks'} = @locations;
	    $stats{$year}{'max-peaks-URL'} = $report->get_report_page_url();
	}

	if (defined $gain) {
	    $gain = Scramble::Misc::numerify($gain);
	    if (! defined $stats{$year}{'max-gain'} or $stats{$year}{'max-gain'} < $gain) {
		$stats{$year}{'max-gain'} = $gain;
		$stats{$year}{'max-gain-URL'} = $report->get_report_page_url();
	    }
	    my $gain_per_day = $gain / $report->get_num_days();
	    if (! defined $stats{$year}{'max-gain-per-day'} or $stats{$year}{'max-gain-per-day'} < $gain_per_day) {
		$stats{$year}{'max-gain-per-day'} = $gain_per_day;
		$stats{$year}{'max-gain-per-day-URL'} = $report->get_report_page_url();
	    }
	    
	    $stats{$year}{'elevation-gain'} += $gain;
	    $stats{$year}{'gain-count'}++;
	    
	}
    }
    my $html = qq(<tr>
		  <th>Year</th>
		  <th>Total trips</th>
		  <th>Climbing trips</th>
		  <th>Trail Run trips</th>
		  <th>Total days</th>
		  <th>Climbing days</th>
		  <th>Trail Run days</th>
		  <th>Total peaks</th>
		  <th>Max gain in one trip</th>
		  <th>Max gain per day in one trip</th>
		  <th>Most peaks in one trip</th>
		  </tr>);
    foreach my $year (sort keys %stats) {
        my $formatted_average_gain = '?';
        my $average_gain_per_trip = '?';
        my $formatted_estimated_gain = '?';
        my $formatted_max_gain = '?';
        my $formatted_max_gain_per_day = '?';
        if (defined $stats{$year}{'gain-count'} && $stats{$year}{'gain-count'} > 0) {
            $formatted_max_gain_per_day = Scramble::Misc::format_elevation_short($stats{$year}{'max-gain-per-day'});
            $formatted_max_gain = Scramble::Misc::format_elevation_short($stats{$year}{'max-gain'});
            $stats{$year}{'average-gain'} = int($stats{$year}{'elevation-gain'} / $stats{$year}{'gain-count'});
            $formatted_average_gain = Scramble::Misc::format_elevation_short($stats{$year}{'average-gain'});
            $stats{$year}{'estimated-gain'} = $stats{$year}{'average-gain'} * $stats{$year}{'total-trips'};
            $formatted_estimated_gain = Scramble::Misc::format_elevation_short($stats{$year}{'estimated-gain'});
            $average_gain_per_trip = sprintf("%.2f", $stats{$year}{'average-gain'} * $stats{$year}{'total-trips'} / 5280);
        }
	$html .= sprintf(qq(<tr>
			    <td><a href="%s">%d</a></td>
			    <td align=right>%d</td> <!-- total trips -->
			    <td align=right>%d</td>
			    <td align=right>%d</td>
			    <td align=right>%d</td> <!-- total days -->
			    <td align=right>%d</td>
			    <td align=right>%d</td>
			    <td align=right>%d</td> <!-- total peaks -->
			    <td align=right><a href="%s">%s</a></td> <!-- max gain in one trip -->
			    <td align=right><a href="%s">%s</a></td> <!-- max gain in one day -->
			    <td align=right><a href="%s">%d</a></td> <!-- max peaks -->
			    </tr>),
			 "../../g/r/$year.html",
			 $year,
			 nlvl($stats{$year}{'total-trips'}, 0),
                         nlvl($stats{$year}{'climbing-trips'}, 0),
                         nlvl($stats{$year}{'trail-run-trips'}, 0),
			 nlvl($stats{$year}{'total-days'}, 0),
                         nlvl($stats{$year}{'climbing-days'}, 0),
                         nlvl($stats{$year}{'trail-run-days'}, 0),
			 nlvl($stats{$year}{'total-peaks'}, 0),
			 nlvl($stats{$year}{'max-gain-URL'}, "?"),
			 $formatted_max_gain,
			 nlvl($stats{$year}{'max-gain-per-day-URL'}, "?"),
			 $formatted_max_gain_per_day,
			 nlvl($stats{$year}{'max-peaks-URL'}, "?"),
			 nlvl($stats{$year}{'max-peaks'}, 0));
    }

    $html = Scramble::Misc::make_optional_line("<h2>Stats</h2> <table border=1>%s</table>",
                                               $html);
    my $this_year  = Date::Manip::UnixDate("today", "%Y");
    if (exists $stats{$this_year}) {
        $html .= "<h2>Projections for $this_year</h2>";
        my $day_of_year = Date::Manip::UnixDate("today", "%j");
        $html .= Scramble::Misc::make_colon_line("Number of days",
                                                 sprintf("%d", (365/$day_of_year) * get_total_days($stats{$this_year})));
        $html .= Scramble::Misc::make_colon_line("Number of trips",
                                                 sprintf("%d", (365/$day_of_year) * $stats{$this_year}{'total-trips'}));
        $html .= Scramble::Misc::make_colon_line("Number of climbing trips",
                                                 sprintf("%d", (365/$day_of_year) * $stats{$this_year}{'climbing-trips'}));
        $html .= Scramble::Misc::make_colon_line("Number of trail run trips",
                                                 sprintf("%d", (365/$day_of_year) * $stats{$this_year}{'trail-run-trips'}));
        $html .= Scramble::Misc::make_colon_line("Number of peaks",
                                                 sprintf("%d", (365/$day_of_year) * $stats{$this_year}{'total-peaks'}));
    }

    return $html;
}

sub get_total_climbed {
    my $unique_count = 0;
    my $summit_count = 0;
    my %climbed;
    foreach my $location (Scramble::Location::get_visited()) {
	next if ! ($location->get_type() eq 'peak'
                   || (defined $location->get_prominence()
                       && $location->get_prominence() > 400));
        my $count = scalar(grep { $_->get_state() eq 'done' } Scramble::Report::get_reports_for_location($location));
        next unless $count;
	$unique_count++;
        $summit_count += $count;
        if ($count > 3) {
            $climbed{$location->get_name()} = $count;
        }
    }

    my @most_climbed;
    foreach my $name (sort { $climbed{$b} <=> $climbed{$a} } keys %climbed) {
        push @most_climbed, Scramble::Misc::htmlify("Climbed $name $climbed{$name} times.");
    }

    return ('unique-count' => $unique_count,
            'total-count' => $summit_count,
            'most-climbed-text' => \@most_climbed);
}

sub make_page {
    my %peak_info = get_total_climbed();

    my $total_climbed_html
        = sprintf("%s unique peaks climbed.<br>%s total peaks climbed (including %s repeats).<br>",
                  Scramble::Misc::commafy($peak_info{'unique-count'}),
                  Scramble::Misc::commafy($peak_info{'total-count'}),
                  Scramble::Misc::commafy($peak_info{'total-count'} - $peak_info{'unique-count'}));

    my $most_climbed = join("<br>", @{ $peak_info{'most-climbed-text'} });

    my $list_html = get_list_html();
    my $stats_html = get_stats();

    my $html = <<EOT;
$total_climbed_html
$list_html
$stats_html
<h2>Most Climbed Peaks</h2>
$most_climbed
EOT

    Scramble::Misc::create("m/geekery.html",
                           Scramble::Misc::make_1_column_page(title => "Numbers",
                                                              'include-header' => 1,
                                                              html => $html));
}

1;
