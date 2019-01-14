package Scramble::Converter;

use strict;

sub convert_locations {
    my $data_directory = shift;
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

        my $path = sprintf("$data_directory/locations/%s.xml", Scramble::Misc::sanitize_for_filename($locations[0]->get_name()));

	my $fh = IO::File->new($path, 'w') or die "Failed to create $path: $!";
	$fh->print($converter->convert(@locations) . "\n") or die;
	$fh->close() or die;
        Scramble::Model::parse($path);
    }
}

sub get_converted_trip_path {
    my ($data_directory, $trip) = @_;


    my %args = (
                'trip-id' => $trip->get_trip_id(),
                'date' => $trip->get_start_date(),
               );
    my @images = Scramble::Model::Image::get_all_images_collection()->find(%args);
    if (@images) {
	return sprintf("%s/trip.xml", $images[0]->get_source_directory());
    }

    my $subdir = File::Basename::basename($trip->{path});
    $subdir =~ s/\.xml$//;
    $subdir = "$data_directory/gabrielx/trips/$subdir";
    File::Path::mkpath([ $subdir ], 0, 0755);

    return "$subdir/trip.xml";
}

sub convert_trips {
    my $data_directory = shift;
    my @files = @_;

    my $converter = Scramble::Converter::Trip->new();

    @files = glob("$data_directory/gabrielx/trips/*.xml") unless @files;

    foreach my $file (@files) {
	my @trips;
	my $trip = Scramble::Model::Trip->new($file);
	next unless $trip;

        my $path = get_converted_trip_path($data_directory, $trip);
	
	my $fh = IO::File->new($path, 'w') or die "Failed to create $path: $!";
	$fh->print($converter->convert($trip) . "\n") or die;
	$fh->close() or die;

        Scramble::Model::parse($path);
    }
}

1;
