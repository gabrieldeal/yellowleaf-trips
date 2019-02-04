package Scramble::Ingestion::Trip;

use strict;

use Data::Dumper ();
use File::Basename ();
use File::Spec ();
use Geo::Gpx ();
use IO::File ();
use Image::ExifTool ();
use Scramble::Controller::TripXml ();
use Scramble::Misc qw(my_system);
use Scramble::Model::Area ();
use Scramble::Model::Location ();
use Scramble::Time ();
use Spreadsheet::Read ();

# FIXME: Refactor everything

sub create {
    my (%args) = @_;

    $ENV{TZ} || die "Set Timezone.  E.g., export TZ='America/Los_Angeles'";
    defined $args{title} or die "Missing arguments: image-subdir trip-type title";

    my $trip_files_src_dir = "$args{files_src_dir}/$args{trip_files_subdir}";
    -d $trip_files_src_dir or die "Non-existant image dir: $trip_files_src_dir";

    my ($date) = ($args{trip_files_subdir} =~ /^(\d{4}-\d\d-\d\d)/);
    defined $date or die "Unable to get date from image subdirectory: $args{trip_files_subdir}";

    # FIXME: Move this into Scramble::Build::Files.
    create_kml($trip_files_src_dir);

    my $files = read_trip_files($trip_files_src_dir);
    my $timestamps = get_timestamps($files);

    File::Path::mkpath([$args{output_dir}], 0, 0755);
    my $trip_xml_file = "$args{output_dir}/trip.xml";
    if (-e $trip_xml_file) {
        print "$trip_xml_file already exists\n";
    } else {
        my @locations = prompt_for_locations($args{xml_src_dir});
        my $sections = read_trip_sections($args{spreadsheet_filename});
        my $trip_xml = Scramble::Controller::TripXml::html(date => $date,
                                                           title => $args{title},
                                                           trip_type => $args{type},
                                                           locations => \@locations,
                                                           sections => $sections,
                                                           timestamps => $timestamps,
                                                           files => $files,
                                                           trip_files_subdir => $args{trip_files_subdir});
        write_file($trip_xml_file, $trip_xml);
    }

    my $glob = "$trip_files_src_dir/*";
    my @files = glob($glob);
    if (@files) {
        chmod(0744, @files) || die "Failed to chmod ($!) '$glob'";
    }
}

sub get_image_metadata {
    my ($file) = @_;

    print "Reading metadata in $file...\n";
    my @tags = qw(Description ImageDescription Rating DateCreated CreateDate Creator Copyright);
    my $info = Image::ExifTool::ImageInfo($file, \@tags);
    die "Error opening $file: " . $info->{Error} if exists $info->{Error};
    print "Warning opening $file: " . $info->{Warning} if exists $info->{Warning};

    my $timestamp = $info->{'DateCreated (1)'} || $info->{DateCreated} || $info->{CreateDate} or warn "Missing date in '$file': " . Data::Dumper::Dumper($info);
    if (defined $timestamp) {
        $timestamp =~ s{^(\d{4}):(\d\d):(\d\d)}{$1/$2/$3};
        $timestamp =~ s/\.\d\d\d$//;
    }

    my $caption = $info->{'ImageDescription'} || $info->{'Description'} || '';
    $caption = '' if $caption eq "OLYMPUS DIGITAL CAMERA";
    $caption =~ s/&/&amp;/g;
    $caption =~ s/"/&quot;/g;

    return {
        rating => $info->{'Rating (1)'} || $info->{Rating},
        timestamp => $timestamp,
        caption => $caption,
        creator => $info->{Creator},
        copyright => $info->{Copyright},
    };
}

sub convert_date_time {
    my ($epoch_time) = @_;

    my (undef, $minute, $hour, $day, $mon, $year) = localtime($epoch_time);
    $year += 1900;
    $mon += 1;

    return sprintf("$year/%02d/%02d %02d:%02d", $mon, $day, $hour, $minute);
}

sub get_gpx_metadata {
    my ($file) = @_;

    my $path = $file->{'dir'} . '/' . $file->{enl_filename};

    print "Reading $path...\n";

    my $xml = Scramble::Misc::slurp($path);
    my $gpx = Geo::Gpx->new(xml => $xml);
    my $points = $gpx->tracks->[0]{segments}[0]{points};
    my $start = $points->[0]{time};
    my $end = $points->[-1]{time};

    return (
        start => convert_date_time($start),
        end => convert_date_time($end)
        );
}

sub get_gpx_timestamps {
    my ($images) = @_;

    my @gpx_files = grep { $_->{type} eq 'gps' } @$images;

    return {} unless @gpx_files;

    my %first_gpx = get_gpx_metadata($gpx_files[0]);

    my %last_gpx;
    if (@gpx_files == 1) {
        %last_gpx = %first_gpx;
    } else {
        %last_gpx = metadata_from_gpx($gpx_files[-1]);
    }

    return {
        start => $first_gpx{start},
        end => $last_gpx{end}
    };
}

sub get_image_timestamps {
    my ($trip_files) = @_;

    my ($first_timestamp, $last_timestamp);
    foreach my $trip_file (@$trip_files) {
        $last_timestamp = $trip_file->{timestamp};
        if (! defined $first_timestamp && defined $trip_file->{timestamp}) {
            $first_timestamp = $trip_file->{timestamp};
        }
    }

    return {
        start => $first_timestamp,
        end => $last_timestamp,
    };
}

sub get_timestamps {
    my ($files) = @_;

    my $timestamps = get_gpx_timestamps($files);
    if ($timestamps->{start} && $timestamps->{end}) {
        return $timestamps;
    }

    return get_image_timestamps($files);
}

sub read_trip_sections {
    my ($spreadsheet_filename) = @_;

    return {} unless $spreadsheet_filename;
    my $book = Spreadsheet::Read->new($spreadsheet_filename);
    my $sheet = $book->sheet(1);
    my @rows = $sheet->rows;

    my $header = shift @rows;
    my $index = 0;
    my %column_index = map { ($_, $index++) } @$header;

    my %sections;
    for my $row (@rows) {
        next unless $row->[$column_index{Date}] && $row->[$column_index{Name}] && defined $row->[$column_index{Day}];
        $sections{$row->[$column_index{Date}]} = "Day $row->[$column_index{Day}]: to $row->[$column_index{Name}]";
    }

    return \%sections;
}

sub get_first_quad_name {
    my ($location) = @_;

    my @quads = $location->get_quad_objects;
    if (! @quads) {
        die sprintf("No quad found for %s", $location->get_name);
    }

    return $quads[0]{name};
}

sub prompt_for_locations {
    my ($xml_src_dir) = @_;

    my @locations;

    my $prompt = "Location (^D to quit): ";
    print $prompt;
    Scramble::Model::Area::open($xml_src_dir);
    Scramble::Model::Location::set_xml_src_directory($xml_src_dir);
    my %opened_locations;
    while (my $location_name = <STDIN>) {
        my @location_matches;
        my $location_regex = "\Q". join('\E.*\Q', split(/\s+/, $location_name)) . "\E";
        foreach my $location_path (glob("$Scramble::Model::Location::LOCATION_XML_SRC_DIRECTORY/*.xml")) {
            my $location_filename = File::Basename::basename($location_path);
            if ($location_filename =~ /$location_regex/i) {
                if ($opened_locations{$location_filename}) {
                    @location_matches = @{ $opened_locations{$location_filename} };
                } else {
                    push @location_matches, Scramble::Model::Location::open_specific($location_path);
                    $opened_locations{$location_filename} = \@location_matches;
                }
            }

        }
        if (!@location_matches) {
            print "No matches\n\n";
            print $prompt;
            next;
        }

        my @location_choices = map {
            { name => sprintf("%s (%s)", $_->get_name, get_first_quad_name($_)),
              value => $_
            }
        } @location_matches;
        my $location = Scramble::Misc::choose_interactive(@location_choices);

        push @locations, $location if $location;

        print $prompt;
    }
    print "\n";

    return @locations;
}

sub glob_trip_files {
    my ($dir) = @_;

    my @filenames;
    push @filenames, glob "$dir/*.{kml,gpx}";
    push @filenames, glob "$dir/*-enl\.{jpg,png}";
    push @filenames, glob "$dir/*.{mp4,MP4,MOV,mov}";
    @filenames = sort @filenames;

    return @filenames;
}

sub read_trip_files {
    my ($dir) = @_;

    print "Reading images in $dir...\n";

    -d $dir or die "No such directory '$dir'";
    $dir =~ s{/*$}{};

    my @filenames = glob_trip_files($dir);

    my @files;
    foreach my $enl_filename (@filenames) {
        next if $enl_filename =~ /\.mp4$/i && $enl_filename !~ /-renc.mp4$/i;
        $enl_filename =~ s,.*/,,;

        my ($type, $caption, $owner, $rating, $timestamp, $orig_filename);
	if ($enl_filename =~ /\.(gpx)$/i) {
	    $type = "gps";
        } elsif ($enl_filename =~ /\.(kml)$/i) {
	    $type = "kml";
        } elsif ($enl_filename =~ /\broute\b/ or $enl_filename =~ /\bmap\b/) {
	    $type = "map" ;
	} else {
            $type = $enl_filename =~ /\.(mp4|mov)$/i ? 'movie' : 'picture';

            my $orig_filename = get_original_filename($dir, $enl_filename, $type);
            my $metadata = get_image_metadata("$dir/$orig_filename");

            if ($type ne 'movie') {
                $rating = get_rating($metadata->{rating});
            }
            $caption = $metadata->{'caption'} || '';
            $owner = $metadata->{creator} || $metadata->{copyright} || 'Gabriel Deal';
            $timestamp = $metadata->{'timestamp'};
	}

	my $thumb_filename = $enl_filename;
        if ($type ne 'gps' && $type ne 'kml' && $type ne 'movie') {
            my ($base, $ext) = ($enl_filename =~ /^(.*)-enl\.(\w+)$/) or die "$enl_filename, $type";
            $thumb_filename = "$base-small.$ext";
            if (! -e "$dir/$thumb_filename") {
                $thumb_filename = "$base.$ext"; # Old thumbnail filename format
            }
            if (! -e "$dir/$thumb_filename") {
                die "Unable to find thumb file for '$enl_filename'";
            }
        }

        push @files, {
	    dir => $dir,
            orig_filename => $orig_filename,
            thumb_filename => $thumb_filename,
	    enl_filename => $enl_filename,
	    type => $type,
	    caption => $caption,
            owner => $owner,
            rating => $rating,
            timestamp => $timestamp,
        };
    }

    return \@files;
}

sub get_original_filename {
    my ($src_dir, $enl_filename, $type) = @_;

    my $orig_prefix;
    if ($type eq 'movie') {
        ($orig_prefix) = ($enl_filename =~ /^(.*)-renc.(mp4|mov)$/i);
    } else {
        # Older processed files start with "<NNNNN>-"
        ($orig_prefix) = ($enl_filename =~ /^(?:\d+-)?([-\w_\(\)]+)-enl.jpg$/);
    }
    $orig_prefix or die "Failed to parse '$enl_filename'";

    my @extensions = map { ($_, uc($_)) } qw(xmp dng jpg mov mp4);
    foreach my $extension (@extensions) {
        my $orig_filename = "$orig_prefix.$extension";
        my $orig_path = "$src_dir/$orig_filename";
        return $orig_filename if -e $orig_path;
    }

    die qq(Unable to find metadata file matching "$src_dir/$orig_prefix.*");
}

sub get_rating {
    my ($rating) = @_;

    if (! defined $rating) {
        die "Missing rating";
    } elsif ($rating == 1) {
        return 3;
    } elsif ($rating == 2) {
        return 2;
    } elsif ($rating == 3) {
        return 1;
    } else {
        die "Out-of-bounds rating '$rating'.  Must be 1, 2, or 3.";
    }
}

sub create_kml {
    my ($dir) = @_;

    my @gpx_paths = sort(glob "$dir/*.gpx");
    return unless @gpx_paths;

    # gpsconvert chokes on cygwin-style paths.
    my $kml_path = File::Spec->abs2rel("$dir/route.kml");
    return if -e $kml_path;

    my @gpx_args;
    foreach my $gpx_path (@gpx_paths) {
        push @gpx_args, File::Spec->abs2rel($gpx_path);
    }

    my $gpsconvert = File::Basename::dirname($0) . "/gpsconvert";

    my_system($gpsconvert,
              '--no-waypoints',
              '--simplify',
              @gpx_args,
              '-o', $kml_path);
}

sub write_file {
    my ($filename, $content) = @_;

    die "$filename already exists" if -e $filename;

    print "Creating $filename\n";
    my $fh = IO::File->new($filename, "w");
    $fh || die "Can't open '$filename': $!";
    $fh->print($content);
    $fh->close or die "Error writing to '$filename': $!";
}

1;
