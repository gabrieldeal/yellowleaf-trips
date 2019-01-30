package Scramble::Controller::MapFragment;

use strict;

sub params {
    my ($locations, $options) = @_;

    my (@inputs);

    @$locations = map { $_->get_latitude() ? ($_) : () } @$locations;
    if (@$locations) {
	my $points_json = _get_point_json(@$locations);
	my $encoded_points_json = URI::Encode::uri_encode($points_json);
        push @inputs, {
            name => 'points',
            value => $points_json
        };
    }

    if ($options->{'kml-url'}) {
        my $escaped_kml_url = URI::Encode::uri_encode($options->{'kml-url'});
        push @inputs, {
            name => 'kmlUrl',
            value => "'$escaped_kml_url'"
        };
    }

    return @inputs;
}

sub html {
    my ($locations, $options) = @_;

    my (@inputs) = params($locations, $options);
    return '' unless @inputs;

    my $template = Scramble::Template::create('shared/map');
    $template->param(map_inputs => \@inputs);

    return $template->output();
}

sub _get_point_json {
    my (@locations) = @_;

    @locations or die "Missing locations";

    my @points;
    foreach my $location (@locations) {
        my $lat = $location->get_latitude();
        my $lon = $location->get_longitude();
        my $name = $location->get_name();
        push @points, qq({"lat":$lat,"lon":$lon,"name":"$name"});
    }

    return sprintf("[%s]", join(",", @points));
}

1;
