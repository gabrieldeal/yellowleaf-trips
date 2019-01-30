package Scramble::Controller::LocationPage;

use strict;

use Scramble::Controller::MapFragment ();
use Scramble::Controller::TripFragment ();
use Scramble::Htmlify ();
use Scramble::Misc ();
use Scramble::Template ();

sub new {
    my ($arg0, $location) = @_;

    my $self = {
        location => $location,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create_all {
    my @locations = (Scramble::Model::Location::get_visited(),
                     Scramble::Model::Location::get_unvisited());
    @locations = sort { lc($a->get_filename()) cmp lc($b->get_filename()) } @locations;

    foreach my $location (@locations) {
        my $page = Scramble::Controller::LocationPage->new($location);
        $page->create();
    }
}

sub create {
    my $self = shift;

    my $location = $self->{location};
    my @map_inputs = Scramble::Controller::MapFragment::params([ $self->{location} ]);
    my @image_params = map {
        Scramble::Controller::ImageFragment->new($_)->params;
    } $location->get_picture_objects;

    my %params = (
        aka => to_comma_separated_list($self->{location}->get_aka_names()),
        counties => to_comma_separated_list($self->get_counties()),
        description_html => Scramble::Htmlify::htmlify($location->get_description()),
        elevation => Scramble::Controller::ElevationFragment::format_elevation($location->get_elevation()),
        images => \@image_params,
        map_inputs => \@map_inputs,
        name_origin_html => Scramble::Htmlify::htmlify($location->get_naming_origin()),
        prominence => Scramble::Controller::ElevationFragment::format_elevation($location->get_prominence()),
        recognizable_areas => to_comma_separated_list($self->get_recognizable_areas()),
        state => $self->get_state(),
        trips => $self->get_trips_params(),
        usgs_quads => to_comma_separated_list($self->get_quads()),
        );

    my $html = Scramble::Template::html('location/page', \%params);

    Scramble::Misc::create(sprintf("l/%s", $location->get_filename()),
                           Scramble::Template::page_html(title => $self->get_title,
                                                         'include-header' => 1,
                                                         html => $html,
                                                         'no-add-picture' => 1,
                                                         'enable-embedded-google-map' => 1));
}

sub to_comma_separated_list {
    my @elements = @_;

    my $delim = grep(/,/, @elements) ? ';' : ',';

    return join("$delim ", @elements);
}

sub get_title {
    my $self = shift;

    my $title = sprintf("Location: %s", $self->{location}->get_name());
    if ($self->{location}->get_is_unofficial_name()) {
        $title .= " (unofficial name)";
    }

    return $title;
}

sub get_recognizable_areas {
    my $self = shift;

    my @areas = $self->{location}->get_recognizable_areas();
    return map { $_->get_short_name() } @areas;
}

sub get_quads {
    my $self = shift;

    return map { $_->get_short_name() } $self->{location}->get_quad_objects();
}

sub get_counties {
    my $self = shift;

    return map { $_->get_short_name() } $self->{location}->get_county_objects();
}

sub get_state {
    my $self = shift;

    if (! $self->{location}->get_state_object()) {
      return undef;
    }
    return $self->{location}->get_state_object()->get_short_name();
}

sub get_trips_params {
    my $self = shift;

    my @trips = Scramble::Model::Trip::get_trips_for_location($self->{location});
    my @trip_params;
    foreach my $trip (@trips) {
        next unless $trip->should_show();

        push @trip_params, {
            date => Scramble::Controller::TripFragment::get_date_summary($trip),
            name => $trip->get_name,
            url => $trip->get_trip_page_url,
        };
    }

    return \@trip_params;
}

1;
