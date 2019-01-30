package Scramble::Controller::TripPage;

# The page about one particular trip.  E.g., /scramble/g/r/2018-10-06-little-giant.html

use strict;

use Scramble::Htmlify ();
use Scramble::Misc ();
use Scramble::Controller::MapFragment ();
use Scramble::Controller::WaypointsFragment ();

sub new {
    my ($arg0, $trip) = @_;

    my $self = {
        trip => $trip,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub trip { $_[0]{trip} }

sub create {
    my $self = shift;

    my $params = {
        route_html => Scramble::Htmlify::htmlify($self->trip()->get_route()),
        sections => $self->get_sections_params,
    };
    my $html = Scramble::Template::html('trip/page', $params);

    Scramble::Misc::create(sprintf("r/%s", $self->trip()->get_filename()),
                           Scramble::Template::page_html('title' => $self->get_title,
                                                         'include-header' => 1,
                                                         'html' => $html,
                                                         'enable-embedded-google-map' => 1));
}

sub get_title {
    my $self = shift;

    my $title = $self->trip->get_name;
    if ($self->trip->get_state eq 'attempted') {
      $title .= sprintf(" (%s)", $self->trip->get_state);
    }

    return $title;
}

sub get_elevation_gain {
    my $self = shift;

    return $self->trip->get_waypoints->get_elevation_gain("ascending|descending");
}

sub get_time_params {
    my $self = shift;

    my $waypoints = $self->trip()->get_waypoints();

    if ($waypoints->get_waypoints_with_times() <= 2) {
        # Some trips have zero waypoints but still have a car-to-car time.
        return (
            short_time => Scramble::Controller::WaypointsFragment::get_short($waypoints),
            );
    }

    return (
        detailed_times_html => Scramble::Controller::WaypointsFragment::get_detailed_html($waypoints),
        );
}

sub get_references_params {
    my $self = shift;

    my @references = $self->trip->get_references;;

    if (@references == 0) {
        return ();
    } elsif (@references == 1) {
        return %{ Scramble::Controller::ReferenceFragment->new($references[0])->short_params };
    } else {
        my @params = map { Scramble::Controller::ReferenceFragment->new($_)->params } @references;

        return (references => \@params);
    }
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

    return sprintf("%s %s%s",
		   $total_miles,
		   Scramble::Misc::pluralize($total_miles, 'mile'),
		   (@parenthesis_htmls == 1 ? '' : " (" . join(", ", @parenthesis_htmls) . ")"));
}

sub get_map_params {
    my $self = shift;

    return [] if $self->trip()->get_map_objects();

    my @locations = $self->trip()->get_location_objects();
    my $kml_url = $self->trip()->get_kml() ? $self->trip()->get_kml()->get_full_url() : undef;
    return [] unless $kml_url or grep { defined $_->get_latitude() } @locations;

    my %options = ('kml-url' => $kml_url);
    return [Scramble::Controller::MapFragment::params(\@locations, \%options)];
}

sub get_maps_summary_params {
    my $self = shift;

    return () if $self->trip()->no_maps();

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
    return () unless @maps;
    return () if @maps > 15;

    my $title = Scramble::Misc::pluralize(scalar(@maps), $type);

    return (
        maps_title => $title,
        maps => join(", ", @maps),
        );
}

sub get_recognizable_areas {
    my $self = shift;

    my @areas = $self->{trip}->get_recognizable_areas();
    my @names = map { $_->get_short_name() } @areas;

    return join(", ", @names);
}

sub get_sections_params {
    my $self = shift;

    my $first_section_params = {
        $self->get_time_params,
        $self->get_maps_summary_params,
        $self->get_references_params,
        start_date => $self->trip->get_start_date,
        end_date => $self->trip->get_end_date,
        trip_type => $self->trip->get_type,
        distances_html => $self->get_distances_html,
        elevation_gain => $self->get_elevation_gain,
        map_inputs => $self->get_map_params,
        recognizable_areas => $self->get_recognizable_areas,
    };

    my @sections_params;
    my @sections = $self->split_pictures_into_sections;

    if (@sections > 1) {
        push @sections_params, $first_section_params;
        $first_section_params = {};
    }

    foreach my $section (@sections) {
        my @image_params = map {
            Scramble::Controller::ImageFragment->new($_)->params('no-trip-date' => 1);
        } @{ $section->{pictures} };

        push @sections_params, {
            %$first_section_params,
            images => \@image_params,
            name => @sections > 1 ? $section->{name} : undef,
        };

        $first_section_params = {};
    }

    return \@sections_params;
}

sub split_pictures_into_sections {
    my $self = shift;

    my @map_images = $self->trip->get_map_objects;

    my @picture_objs = $self->trip()->get_picture_objects();
    return ({ name => '', pictures => \@map_images}) unless @picture_objs;

    my @sections;
    if (@picture_objs[0]->get_section_name()) {
        @sections = $self->split_by_section_name(@picture_objs);
    } else {
        my $split_picture_objs = $self->split_by_date(@picture_objs);
        @sections = $self->add_section_names($split_picture_objs);
    }

    unshift @{ $sections[0]{pictures} }, @map_images;

    return @sections;
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
