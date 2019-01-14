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

sub get_converted_report_path {
    my ($data_directory, $report) = @_;


    my %args = (
                'trip-id' => $report->get_trip_id(),
                'date' => $report->get_start_date(),
               );
    my @images = Scramble::Model::Image::get_all_images_collection()->find(%args);
    if (@images) {
	return sprintf("%s/report.xml", $images[0]->get_source_directory());
    }

    my $subdir = File::Basename::basename($report->{path});
    $subdir =~ s/\.xml$//;
    $subdir = "$data_directory/gabrielx/reports/$subdir";
    File::Path::mkpath([ $subdir ], 0, 0755);

    return "$subdir/report.xml";
}

sub convert_reports {
    my $data_directory = shift;
    my @files = @_;

    my $converter = Scramble::Converter::Trip->new();

    @files = glob("$data_directory/gabrielx/reports/*.xml") unless @files;

    foreach my $file (@files) {
	my @reports;
	my $report = Scramble::Model::Trip->new($file);
	next unless $report;

        my $path = get_converted_report_path($data_directory, $report);
	
	my $fh = IO::File->new($path, 'w') or die "Failed to create $path: $!";
	$fh->print($converter->convert($report) . "\n") or die;
	$fh->close() or die;

        Scramble::Model::parse($path);
    }
}

1;
