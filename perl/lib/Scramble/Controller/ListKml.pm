package Scramble::Controller::ListKml;

use strict;

use Scramble::Model::List ();
use Scramble::Misc ();

# FIXME: Refactor display code into a template.

sub new {
    my ($arg0, $list) = @_;

    my $self = {
        list => $list,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create_all {
    my ($writer) = @_;

    foreach my $list (Scramble::Model::List::get_all()) {
        if ($list->should_skip) {
            next;
        }

        Scramble::Logger::verbose("Making list KML for " . $list->get_name . "\n");
        Scramble::Controller::ListKml->new($list)->create($writer);
    }
}

sub create {
    my $self = shift;
    my ($writer) = @_;

    my $list = $self->{list};

    my $kml = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://earth.google.com/kml/2.1">
EOT
    foreach my $list_location ($list->get_locations) {
        my $location = $list_location->get_location_object;
        if (! $location) {
            next;
        }
        my $name = $location->get_name();
        my $lat = $location->get_latitude();
        if (! defined $lat) {
            next;
        }
        my $lon = $location->get_longitude();
        $kml .= <<EOT;
  <Placemark>
    <name>$name</name>
    <description>$name</description>
    <Point>
      <coordinates>$lon,$lat</coordinates>
    </Point>
  </Placemark>
EOT
    }

    $kml .= "</kml>";

    my $path = $list->get_kml_path;
    $writer->create($path, $kml);
}

1;
