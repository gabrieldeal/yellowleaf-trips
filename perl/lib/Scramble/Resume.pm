package Scramble::Resume;

use strict;

sub make_resume_page {
    my $in_scramble_mode=0;

    my $html .= <<EOT;
<Table border=1>
<tr><th>Date</th><th>Trip</th><th>Type</th><th>Organizer</th><th>Leader</th></tr>
EOT

    foreach my $report (Scramble::Report::get_all()) {
        next if $report->get_state() eq 'planned';

        next if $in_scramble_mode && $report->get_type() !~ /scramble/i;
        next if $in_scramble_mode && $report->get_state() eq 'attempted';

        my $date = $report->get_start_date();
        if ($report->get_end_date()) {
            $date .= " - " . $report->get_end_date();
        }

        my $name = $report->get_name();
        $name =~ s/\(.*? quad\)//;
        if ($report->get_state() eq 'attempted') {
            $name .= " (attempted)";
        }
        my @rock_routes_text;
        my @rock_routes = $report->get_rock_routes();
        foreach my $route (@rock_routes) {
            push @rock_routes_text, 
                sprintf("%s: %s (%s %s%s)",
                        $route->{location},
                        $route->{name},
                        $route->{rating},
                        $route->{type},
                        $route->{'num-pitches'} ? ", $route->{'num-pitches'} pitches" : "");
        }
        if (@rock_routes_text) {
            $name .= "<ul><li>" . join("<li>", @rock_routes_text) . "</ul>";
        }

        my $leaders = join(", ", $report->get_leaders());

        my $organizer = $report->get_trip_organizer();
        if ($organizer =~ /Mountaineers(.*)Committee/) {
            my $committee = lc($1);
            $organizer = "Mountaineers ($committee)";
            $organizer = "Mountaineers" if $in_scramble_mode;
        }

        $html .= sprintf("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
                         $date,
                         $name,
                         $report->get_type(),
                         $organizer,
                         $leaders || '&nbsp;');
    }
$html .= "</table>";

    Scramble::Misc::create
	    ("m/resume.html",
	     Scramble::Misc::make_2_column_page("Climbing Resume",
                                                $html,
						undef,
                                                'no-links-box' => 1,
                                               'no-add-picture' => 1));
}

1;
