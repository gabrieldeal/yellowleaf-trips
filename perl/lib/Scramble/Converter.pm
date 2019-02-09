package Scramble::Converter;

use strict;

sub convert_locations {
    my $xml_src_dir = shift;
    my @files = @_;

    my $converter = Scramble::Converter::Location->new();

    foreach my $file (@files) {
	my @locations;
	foreach my $location (Scramble::Model::Location->new_objects($file)) {
	    if ($location->get_is_driving_location() or $location->get_is_road()) {
		printf("Skipping %s\n", $location->get_name());
		next;
	    }
	    push @locations, $location;
	}
	next unless @locations;

        my $path = sprintf("$xml_src_dir/locations/%s.xml", Scramble::Misc::sanitize_for_filename($locations[0]->get_name()));

	my $fh = IO::File->new($path, 'w') or die "Failed to create $path: $!";
	$fh->print($converter->convert(@locations) . "\n") or die;
	$fh->close() or die;
        Scramble::Model::parse($path);
    }
}

sub get_converted_trip_path {
    my ($xml_src_dir, $trip) = @_;


    my %args = (
                'trip-id' => $trip->get_trip_id(),
                'date' => $trip->get_start_date(),
               );
    my @images = Scramble::Model::File::get_pictures_collection()->find(%args);
    if (@images) {
        return sprintf("%s/trip.xml", $images[0]->get_trip_files_src_dir());
    }

    my $subdir = File::Basename::basename($trip->{path});
    $subdir =~ s/\.xml$//;
    $subdir = "$xml_src_dir/gabrielx/trips/$subdir";
    File::Path::mkpath([ $subdir ], 0, 0755);

    return "$subdir/trip.xml";
}

sub convert_trips {
    my $xml_src_dir = shift;
    my @files = @_;

    my $converter = Scramble::Converter::Trip->new();

    @files = glob("$xml_src_dir/gabrielx/trips/*.xml") unless @files;

    foreach my $file (@files) {
	my @trips;
	my $trip = Scramble::Model::Trip->new($file);
	next unless $trip;

        my $path = get_converted_trip_path($xml_src_dir, $trip);
	
	my $fh = IO::File->new($path, 'w') or die "Failed to create $path: $!";
	$fh->print($converter->convert($trip) . "\n") or die;
	$fh->close() or die;

        Scramble::Model::parse($path);
    }
}

1;
