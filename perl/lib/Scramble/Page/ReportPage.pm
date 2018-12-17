package Scramble::Page::ReportPage;

# The page about one particular report.  E.g., /scramble/g/r/2018-10-06-little-giant.html

use strict;

use Scramble::Misc ();

sub new {
    my ($arg0, $report) = @_;

    my $self = {
        report => $report,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub report { $_[0]{report} }

sub make_date_html {
    my $self = shift;

    my $date = $self->report()->get_start_date();
    if (defined $self->report()->get_end_date()) {
	$date .= " to " . $self->report()->get_end_date();
    }

    return Scramble::Misc::make_colon_line("Date", $date);
}

sub get_elevation_gain_html {
    my $self = shift;

    return Scramble::Misc::make_optional_line("<b>Elevation gain:</b> approx. %s<br>",
                                              $self->report()->get_waypoints()->get_elevation_gain("ascending|descending"));
}

sub create {
    my $self = shift;

    my $date = $self->make_date_html();
    my $trip_type = Scramble::Misc::make_colon_line("Trip type", $self->report()->get_type());
    my $elevation_html = $self->get_elevation_gain_html();
    my $miles_html = $self->report()->get_distances_html();
    my $quads_html = $self->report()->get_map_summary_html();
    my $recognizable_areas_html = $self->report()->get_recognizable_areas_html('no-link' => 1);
    my $short_route_references = '';
    my $long_route_references = '';
    if ($self->report()->get_references() == 1) {
      $short_route_references = Scramble::Misc::make_colon_line("Reference", 
								Scramble::Model::Reference::get_reference_html_with_name_only($self->report()->get_references(),
                                                                                                                              'name-ids' => [qw(page-name name)]));
    } else {
      $long_route_references = Scramble::Misc::make_optional_line("<h2>References</h2>%s",
							     $self->report()->get_reference_html());
    }

    my $long_times_html = '';
    my $short_times_html = '';
    if ($self->report()->get_waypoints()->get_waypoints_with_times() > 2) {
      $long_times_html = $self->report()->get_waypoints()->get_detailed_time_html();
    } else {
        # Some reports have zero waypoints but still have a car-to-car time.
        $short_times_html = $self->report()->get_waypoints()->get_car_to_car_html();
    }

    my $right_html = <<EOT;
$date
$short_times_html
$miles_html
$elevation_html
$trip_type
$quads_html
$recognizable_areas_html
$short_route_references
$long_times_html
$long_route_references
EOT

    my @htmls;
    push @htmls, $right_html;

    my $map_html = $self->report()->get_embedded_google_map_html();
    push @htmls, $map_html if $map_html;

    my $count = 1;
    my $cells_html;
    my @map_objects = $self->report()->get_map_objects();
    my @sections = $self->report()->split_pictures_into_sections();
    foreach my $section (@sections) {
        if (@sections > 1) {
	    if ($count == 1) {
		$cells_html .= Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
								       'images' => [@map_objects ],
                                                                       'no-report-link' => 1);
		@htmls = @map_objects = ();
                $cells_html .= '<br clear="all" />';
	    }
            $cells_html .= qq(<h2>$section->{name}</h2>);
	}

        $cells_html .= Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
                                                               'images' => [@map_objects, @{ $section->{pictures} } ],
                                                               'no-report-link' => 1);
        $cells_html .= '<br clear="all" />';
        @htmls = @map_objects = ();
        $count++;
    }

    my $route = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("%s", $self->report()->get_route()));
    if ($route) {
	$route = "<p>$route</p>";
    }

    my $title = $self->report()->get_title_html();
    if ($self->report()->get_state() eq 'attempted') {
      $title .= sprintf(" (%s)", $self->report()->get_state());
    }

    my $html = <<EOT;
$route
$cells_html
EOT

    my $copyright_year = $self->report()->get_copyright_html();
    Scramble::Misc::create(sprintf("r/%s", $self->report()->get_filename()),
                           Scramble::Misc::make_1_column_page('title' => $title,
							      'include-header' => 1,
                                                              'html' => $html,
                                                              'enable-embedded-google-map' => $Scramble::Misc::gEnableEmbeddedGoogleMap,
							      'copyright-year' => $copyright_year));
}

######################################################################
# Statics

sub create_all {
    foreach my $report (Scramble::Model::Report::get_all()) {
        eval {
            my $page = Scramble::Page::ReportPage->new($report);
            $page->create();
        };
        if ($@) {
            local $SIG{__DIE__};
            die sprintf("Error while making HTML for %s:\n%s",
                        $report->{'path'},
                        $@);
        }
    }
}


1;
