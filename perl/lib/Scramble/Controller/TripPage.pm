package Scramble::Controller::TripPage;

# The page about one particular trip.  E.g., /scramble/g/r/2018-10-06-little-giant.html

# FIXME: Convert to a template.

use strict;

use Scramble::Misc ();
use Scramble::Controller::WaypointsFragment ();

sub new {
    my ($arg0, $trip) = @_;

    my $self = {
        trip => $trip,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub trip { $_[0]{trip} }

sub make_date_html {
    my $self = shift;

    my $date = $self->trip()->get_start_date();
    if (defined $self->trip()->get_end_date()) {
	$date .= " to " . $self->trip()->get_end_date();
    }

    return Scramble::Misc::make_colon_line("Date", $date);
}

sub get_elevation_gain_html {
    my $self = shift;

    return Scramble::Misc::make_optional_line("<b>Elevation gain:</b> approx. %s<br>",
                                              $self->trip()->get_waypoints()->get_elevation_gain("ascending|descending"));
}

sub create {
    my $self = shift;

    my $date = $self->make_date_html();
    my $trip_type = Scramble::Misc::make_colon_line("Trip type", $self->trip()->get_type());
    my $elevation_html = $self->get_elevation_gain_html();
    my $miles_html = $self->get_distances_html();
    my $quads_html = $self->get_map_summary_html();
    my $recognizable_areas_html = $self->get_recognizable_areas_html();
    my $short_route_references = '';
    my $long_route_references = '';
    if ($self->trip()->get_references() == 1) {
      $short_route_references = Scramble::Misc::make_colon_line("Reference", 
                                                                Scramble::Controller::ReferenceFragment::get_reference_html_with_name_only($self->trip()->get_references()));
    } else {
      $long_route_references = Scramble::Misc::make_optional_line("<h2>References</h2>%s",
                                                             $self->get_reference_html());
    }

    my $waypoints = $self->trip()->get_waypoints();
    my $long_times_html = '';
    my $short_times_html = '';
    if ($waypoints->get_waypoints_with_times() > 2) {
        $long_times_html = Scramble::Controller::WaypointsFragment::get_detailed($waypoints);
    } else {
        # Some trips have zero waypoints but still have a car-to-car time.
        $short_times_html = Scramble::Controller::WaypointsFragment::get_short($waypoints);
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

    my $map_html = $self->get_embedded_google_map_html();
    push @htmls, $map_html if $map_html;

    my $count = 1;
    my $cells_html;
    my @map_objects = $self->trip()->get_map_objects();
    my @sections = $self->split_pictures_into_sections();
    foreach my $section (@sections) {
        if (@sections > 1) {
	    if ($count == 1) {
		$cells_html .= Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
								       'images' => [@map_objects ],
                                                                       'no-trip-link' => 1);
		@htmls = @map_objects = ();
                $cells_html .= '<br clear="all" />';
	    }
            $cells_html .= qq(<h2>$section->{name}</h2>);
	}

        $cells_html .= Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
                                                               'images' => [@map_objects, @{ $section->{pictures} } ],
                                                               'no-trip-link' => 1);
        $cells_html .= '<br clear="all" />';
        @htmls = @map_objects = ();
        $count++;
    }

    my $route = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("%s", $self->trip()->get_route()));
    if ($route) {
	$route = "<p>$route</p>";
    }

    my $title = $self->trip()->get_name();
    if ($self->trip()->get_state() eq 'attempted') {
      $title .= sprintf(" (%s)", $self->trip()->get_state());
    }

    my $html = <<EOT;
$route
$cells_html
EOT

    Scramble::Misc::create(sprintf("r/%s", $self->trip()->get_filename()),
                           Scramble::Misc::make_1_column_page('title' => $title,
							      'include-header' => 1,
                                                              'html' => $html,
                                                              'enable-embedded-google-map' => $Scramble::Misc::gEnableEmbeddedGoogleMap));
}

sub get_distances_html {
    my $self = shift;

    my $distances = $self->trip()->get_round_trip_distances();
    if (! $distances) {
        return '';
    }

    my @parenthesis_htmls;
    my $total_miles = 0;
    foreach my $distance (@$distances) {
	$total_miles += $distance->{'miles'};
	push @parenthesis_htmls, sprintf("%s %s on %s",
					 $distance->{'miles'},
					 Scramble::Misc::pluralize($distance->{'miles'}, "mile"),
					 $distance->{'type'});
    }

    # FIXME: Move into template.
    return sprintf("<b>Round-trip distance:</b> approx. %s %s%s<br>",
		   $total_miles,
		   Scramble::Misc::pluralize($total_miles, 'mile'),
		   (@parenthesis_htmls == 1 ? '' : " (" . join(", ", @parenthesis_htmls) . ")"));
}

sub get_embedded_google_map_html {
    my $self = shift;

    return '' if $self->trip()->get_map_objects();

    my @locations = $self->trip()->get_location_objects();
    my $kml_url = $self->trip()->get_kml() ? $self->trip()->get_kml()->get_full_url() : undef;
    return '' unless $kml_url or grep { defined $_->get_latitude() } @locations;

    my %options = ('kml-url' => $kml_url);
    return Scramble::Misc::get_multi_point_embedded_google_map_html(\@locations, \%options);
}

sub get_reference_html {
    my $self = shift;

    my @references = map { Scramble::Controller::ReferenceFragment::get_page_reference_html($_) } $self->trip()->get_references();
    @references = Scramble::Misc::dedup(@references);

    return '' unless @references;

    return '<ul><li>' . join('</li><li>', @references) . '</li></ul>';
}

sub get_map_summary_html {
    my $self = shift;

    return '' if $self->trip()->no_maps();

    my $type = 'USGS quad';
    my %maps;

    foreach my $map ($self->trip()->get_maps()) {
        my $map_type = $map->{id};
        next unless defined $map_type && $type eq $map_type;
        my $name = $map->{name};
        $maps{$name} = 1;
    }

    if ($type eq 'USGS quad') {
        foreach my $location ($self->trip()->get_location_objects()) {
            foreach my $quad ($location->get_quad_objects()) {
                $maps{$quad->get_short_name()} = 1;
            }
        }

        foreach my $area ($self->trip()->get_areas_collection()->find('type' => 'USGS quad')) {
            $maps{$area->get_short_name()} = 1;
        }
    }

    my @maps = keys %maps;
    return '' unless @maps;
    return '' if @maps > 15;

    my $title = Scramble::Misc::pluralize(scalar(@maps), $type);
    return Scramble::Misc::make_colon_line($title, join(", ", @maps));
}

sub get_recognizable_areas_html {
    my $self = shift;

    my @areas = $self->{trip}->get_recognizable_areas();
    my @names = map { $_->get_short_name() } @areas;

    return Scramble::Misc::make_colon_line("In", join(", ", @names));
}

sub split_pictures_into_sections {
    my $self = shift;

    my @picture_objs = $self->trip()->get_picture_objects();
    return ({ name => '', pictures => []}) unless @picture_objs;

    my @sections;
    if (!@picture_objs[0]->get_section_name()) {
        my $split_picture_objs = $self->split_by_date(@picture_objs);
        return $self->add_section_names($split_picture_objs);
    }

    return $self->split_by_section_name(@picture_objs);
}

sub split_by_section_name {
    my $self = shift;
    my @picture_objs = @_;

    my @sections;
    my %current_section = (name => '', pictures => []);
    foreach my $picture_obj (@picture_objs) {
        if ($picture_obj->get_section_name() && $picture_obj->get_section_name() ne $current_section{name}) {
            push @sections, { %current_section } if @{ $current_section{pictures} };
            %current_section = ( name => $picture_obj->get_section_name(),
                                 pictures => [] );
        }
        push @{ $current_section{pictures} }, $picture_obj;
    }
    push @sections, \%current_section if %current_section;

    return @sections;
}

sub split_by_date {
    my $self = shift;
    my @picture_objs = @_;

    return [] if !@picture_objs;

    my $curr_date = $picture_objs[0]->get_capture_date();
    return [\@picture_objs] unless defined $curr_date;

    my @splits;
    my $split = [];
    foreach my $picture_obj (@picture_objs) {
        if ($curr_date eq $picture_obj->get_capture_date()) {
            push @$split, $picture_obj;
        } else {
            push @splits, $split;
            $split = [ $picture_obj ];
            $curr_date = $picture_obj->get_capture_date();
        }
    }
    push @splits, $split;

    return \@splits;
}

# Return: an array of hashes. Each hash is { name => "", pictures => [] }
sub add_section_names {
    my $self = shift;
    my ($split_picture_objs) = @_; # each element is an array of picture objects

    my $start_days = Scramble::Time::get_days_since_1BC($self->trip()->get_start_date());
    my @sections;
    foreach my $picture_objs (@$split_picture_objs) {
        my $section_name = '';
        # Handle trips where I don't take a picture every day:
        if (@$picture_objs && defined $picture_objs->[0]->get_capture_date()) {
            my $picture_days = Scramble::Time::get_days_since_1BC($picture_objs->[0]->get_capture_date());
            my $day = $picture_days - $start_days + 1;
            $section_name = "Day $day";
        }
        push @sections, { name => $section_name,
                          pictures => $picture_objs };
    }

    return @sections;
}

######################################################################
# Statics

sub create_all {
    foreach my $trip (Scramble::Model::Trip::get_all()) {
        eval {
            my $page = Scramble::Controller::TripPage->new($trip);
            $page->create();
        };
        if ($@) {
            local $SIG{__DIE__};
            die sprintf("Error while making HTML for %s:\n%s",
                        $trip->{'path'},
                        $@);
        }
    }
}


1;
