package Scramble::Controller::LocationPage;

use strict;

use Scramble::Controller::MapFragment ();
use Scramble::Htmlify ();
use Scramble::Misc ();
use Scramble::Template ();

# FIXME: Convert to a template.

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

    my %params = (
        aka => to_comma_separated_list($self->{location}->get_aka_names()),
        counties => to_comma_separated_list($self->get_counties()),
        description_html => Scramble::Htmlify::htmlify($location->get_description()),
        elevation => Scramble::Controller::ElevationFragment::format_elevation($location->get_elevation()),
        name_origin_html => Scramble::Htmlify::htmlify($location->get_naming_origin()),
        prominence => Scramble::Controller::ElevationFragment::format_elevation($location->get_prominence()),
        recognizable_areas => to_comma_separated_list($self->get_recognizable_areas()),
        state => $self->get_state(),
        trips_html => $self->get_trips_for_location_html(),
        usgs_quads => to_comma_separated_list($self->get_quads()),
        );
    my $text_html = Scramble::Template::html('location/page', \%params);

    my @htmls = ($text_html);
    my $map_html =  $self->get_embedded_google_map_html();
    push @htmls, $map_html if $map_html;

    my $title = sprintf("Location: %s", $location->get_name());
    if ($location->get_is_unofficial_name()) {
        $title .= " (unofficial name)";
    }

    my $cells_html = Scramble::Controller::ImageListFragment::html('htmls' => \@htmls,
                                                                   'float-first' => 1,
                                                                   'images' => [ $location->get_picture_objects() ]);

    my $html = <<HTML;
$cells_html
<br clear="all" />
HTML

    Scramble::Misc::create(sprintf("l/%s", $location->get_filename()),
                           Scramble::Template::page_html(title => $title,
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

sub get_embedded_google_map_html {
    my $self = shift;

    return '' unless $self->{location}->get_longitude();

    return Scramble::Controller::MapFragment::html([ $self->{location} ]);
}

sub get_trips_for_location_html {
    my $self = shift;

    my $location = $self->{location};

    my @references_html = Scramble::Controller::ReferenceFragment::get_page_references_html($location->get_references());

    my @trips = Scramble::Model::Trip::get_trips_for_location($location);

    foreach my $trip (@trips) {
        next unless $trip->should_show();
        push @references_html, sprintf("$Scramble::Misc::gSiteName: %s",
                                       $self->get_trip_link_html($trip));
    }

    return '' unless @references_html;

    return '<ul><li>' . join('</li><li>', @references_html) . '</li></ul>';
}

sub get_trip_link_html {
    my $self = shift;
    my ($trip) = @_;

    my $date = $trip->get_summary_date();
    my $name = $trip->get_summary_name();
    my $image_html = $self->get_summary_image_html($trip) || '';
    my $type = $trip->get_type();

    return <<EOT;
<div class="trip-thumbnail">
    <div class="trip-thumbnail-image">$image_html</div>
    <div class="trip-thumbnail-title">$name</div>
    <div class="trip-thumbnail-date">$date</div>
    <div class="trip-thumbnail-type">$type</div>
</div>
EOT
}

sub get_summary_image_html {
    my $self = shift;
    my ($trip) = @_;

    my $size = 125;

    my @image_htmls;
    foreach my $image_obj ($trip->get_sorted_images()) {
        if ($image_obj) {
            my $image_html = sprintf(qq(<img width="$size" onload="Yellowleaf_main.resizeThumbnail(this, $size)" src="%s">),
                                     $image_obj->get_url());
            $image_html = $trip->link_if_should_show($image_html);
            push @image_htmls, $image_html;
        }
    }

    return $image_htmls[0];
}

sub get_formatted_elevation {
    my $self = shift;
    return $self->_get_formatted_elevation(\&Scramble::Controller::ElevationFragment::format_elevation);
}
sub get_short_formatted_elevation {
    my $self = shift;
    return $self->_get_formatted_elevation(\&Scramble::Controller::ElevationFragment::format_elevation_short);
}
sub _get_formatted_elevation {
    my $self = shift;
    my ($format_func) = @_;

    if (defined $self->{location}->get_elevation()) {
	return $format_func->($self->{location}->get_elevation());
    }

    return undef;
}

1;
