package Scramble::Page::ListKml;

use strict;

use Scramble::Model::List ();
use Scramble::Misc ();

# FIXME: Refactor display code into a template.

sub new {
    my ($arg0, $list_xml) = @_;

    my $self = {
        list_xml => $list_xml,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create_all {
    foreach my $list_xml (Scramble::Model::List::get_all_lists()) {
        if ($list_xml->{'skip'}) {
            next;
        }

        Scramble::Logger::verbose("Making list KML for $list_xml->{name}\n");
        Scramble::Page::ListKml->new($list_xml)->create();
    }
}

sub create {
    my $self = shift;

    my $list_xml = $self->{list_xml};

    my $kml = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://earth.google.com/kml/2.1">
EOT
    foreach my $list_location (@{ $list_xml->{'location'} }) {
        my $location = Scramble::Model::List::get_location_object($list_location);
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

    my $path = Scramble::Model::List::get_kml_path($list_xml);
    Scramble::Misc::create($path, $kml);
}

1;
