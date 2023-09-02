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

sub new {
    my ($arg0, %args) = @_;

    my $self = { %args };
    bless($self, ref($arg0) || $arg0);

    return $self;
}

sub create {
    my $self = shift;

    $ENV{TZ} || die "Set Timezone.  E.g., export TZ='America/Los_Angeles'";
    defined $self->{title} or die "Missing title";

    my $trip_files_src_dir = "$self->{files_src_dir}/$self->{trip_files_subdir}";
    -d $trip_files_src_dir or die "Non-existant files dir: $trip_files_src_dir";

    my ($date) = ($self->{trip_files_subdir} =~ /^(\d{4}-\d\d-\d\d)/);
    defined $date or die "Unable to get date from files subdirectory: $self->{trip_files_subdir}";

    my $trip_xml_file = "$self->{output_dir}/trip.xml";
    if (-e $trip_xml_file) {
        print "$trip_xml_file already exists\n";
        return;
    }

    my $files = $self->read_trip_files($trip_files_src_dir);
    push @$files, $self->files_created_by_build($files);

    my $timestamps = $self->get_timestamps($files);

    File::Path::mkpath([$self->{output_dir}], 0, 0755);

    my @locations = $self->prompt_for_locations($self->{xml_src_dir});
    my $sections = $self->read_trip_sections($self->{spreadsheet_filename});
    my $trip_xml = Scramble::Controller::TripXml::html(date => $date,
                                                       title => $self->{title},
                                                       trip_type => $self->{type},
                                                       locations => \@locations,
                                                       sections => $sections,
                                                       timestamps => $timestamps,
                                                       files => $files,
                                                       trip_files_subdir => $self->{trip_files_subdir});
    $self->write_file($trip_xml_file, $trip_xml);
}

sub get_picture_or_video_metadata {
    my $self = shift;
    my ($file) = @_;

    print "Reading metadata in $file...\n";
    my @tags = qw(Description ImageDescription Rating DateCreated CreateDate Creator Copyright Subject);
    my $info = Image::ExifTool::ImageInfo($file) ; #, \@tags);
    die "Error while opening $file: " . $info->{Error} if exists $info->{Error};
    if (exists $info->{Warning} && $info->{Warning} !~ /Bad IDC_IFD SubDirectory/) {
        print "Warning while opening $file: " . $info->{Warning};
    }

    my $timestamp = $info->{'DateCreated (1)'} || $info->{DateCreated} || $info->{CreateDate} || $info->{HistoryWhen} || $info->{MetadataDate} or warn "Missing date in '$file': " . Data::Dumper::Dumper($info);
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
        is_summary => ($info->{Subject} && $info->{Subject} =~ /summary/i),
    };
}

sub convert_date_time {
    my $self = shift;
    my ($epoch_time) = @_;

    my (undef, $minute, $hour, $day, $mon, $year) = localtime($epoch_time);
    $year += 1900;
    $mon += 1;

    return sprintf("$year/%02d/%02d %02d:%02d", $mon, $day, $hour, $minute);
}

sub get_gpx_metadata {
    my $self = shift;
    my ($file) = @_;

    my $path = $file->{'dir'} . '/' . $file->{enl_filename};

    print "Reading $path...\n";

    my $xml = Scramble::Misc::slurp($path);
    my $gpx = Geo::Gpx->new(xml => $xml);
    my $points = $gpx->tracks->[0]{segments}[0]{points};
    my $start = $points->[0]{time};
    my $end = $points->[-1]{time};

    return (
        start => $self->convert_date_time($start),
        end => $self->convert_date_time($end)
        );
}

sub get_gpx_timestamps {
    my $self = shift;
    my ($files) = @_;

    my @gpx_files = grep { $_->{type} eq 'gps' } @$files;

    return {} unless @gpx_files;

    my %first_gpx = $self->get_gpx_metadata($gpx_files[0]);

    my %last_gpx;
    if (@gpx_files == 1) {
        %last_gpx = %first_gpx;
    } else {
        %last_gpx = $self->get_gpx_metadata($gpx_files[-1]);
    }

    return {
        start => $first_gpx{start},
        end => $last_gpx{end}
    };
}

sub get_picture_timestamps {
    my $self = shift;
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
    my $self = shift;
    my ($files) = @_;

    my $timestamps = $self->get_gpx_timestamps($files);
    if ($timestamps->{start} && $timestamps->{end}) {
        return $timestamps;
    }

    return get_picture_timestamps($files);
}

sub read_trip_sections {
    my $self = shift;
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
    my $self = shift;
    my ($location) = @_;

    my @quads = $location->get_quad_objects;
    if (! @quads) {
        die sprintf("No quad found for %s", $location->get_name);
    }

    return $quads[0]{name};
}

sub prompt_for_locations {
    my $self = shift;
    my ($xml_src_dir) = @_;

    my @locations;

    my $prompt = "Location (^D to quit): ";
    print $prompt;
    Scramble::Model::Area::open($xml_src_dir);
    Scramble::Model::Location::set_xml_src_directory($xml_src_dir);
    my %opened_locations;
    while (my $location_name = <STDIN>) {
        my @location_matches;
        my $location_pattern = "\Q" . join("\E.*\Q", split(/\s+/, $location_name)) . "\E";
        my $location_regex = qr/$location_pattern/i;
        foreach my $location_path (glob("$Scramble::Model::Location::LOCATION_XML_SRC_DIRECTORY/*.xml")) {
            my $location_filename = File::Basename::basename($location_path);
            if ($location_filename =~ $location_regex) {
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
            { name => sprintf("%s (%s)", $_->get_name, $self->get_first_quad_name($_)),
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
    my $self = shift;
    my ($dir) = @_;

    my @filenames;
    push @filenames, glob "'$dir/*.{kml,gpx}'";
    push @filenames, glob "'$dir/*-enl\.{jpg,png}'";
    push @filenames, glob "'$dir/*.{mp4,MP4,MOV,mov}'";
    push @filenames, glob "'$dir/*.{wav,WAV}'";
    @filenames = grep { !/-renc.mp4$/i } @filenames;
    @filenames = sort @filenames;

    return @filenames;
}

# FIXME: Refactor this.  Too long.
sub read_trip_files {
    my $self = shift;
    my ($dir) = @_;

    print "Reading files in $dir...\n";

    -d $dir or die "No such directory '$dir'";
    $dir =~ s{/*$}{};

    my @filenames = $self->glob_trip_files($dir);

    my @files;
    foreach my $enl_filename (@filenames) {
        $enl_filename =~ s,.*/,,;

        my ($type, $owner, $rating, $orig_filename, $is_summary);
        my $caption = '';
        my $timestamp = '';
	if ($enl_filename =~ /\.(gpx)$/i) {
	    $type = "gps";
        } elsif ($enl_filename =~ /\.(kml)$/i) {
	    $type = "kml";
        } elsif ($enl_filename =~ /\.wav$/i) {
	    $type = "sound";
        } elsif ($enl_filename =~ /\broute\b/ or $enl_filename =~ /\bmap\b/) {
	    $type = "map" ;
	} else {
            if ($enl_filename !~ /\.(mp4|mov)$/i) {
                $type = 'picture';
                $orig_filename = $self->get_original_filename($dir, $enl_filename, $type);
            } else {
                $type = 'movie';
                $orig_filename = $enl_filename;
                $enl_filename =~ s/\.(mp4|mov)$/-renc.$1/i;
            }

            my $metadata = $self->get_picture_or_video_metadata("$dir/$orig_filename");

            if ($type ne 'movie') {
                $rating = $self->get_rating($metadata);
            }
            $caption = $metadata->{'caption'} || '';
            $owner = $metadata->{creator} || $metadata->{copyright} || 'Gabriel Deal';
            $timestamp = $metadata->{'timestamp'};
            $is_summary = $metadata->{is_summary};
	}

	my $thumb_filename = $enl_filename;
        if ($type ne 'gps' && $type ne 'kml' && $type ne 'movie' && $type ne 'sound') {
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
            is_summary => $is_summary,
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

sub files_created_by_build {
    my $self = shift;
    my ($files) = @_;

    my @gpx_files = grep { $_->{type} eq 'gps' } @$files;
    my @kml_files = grep { $_->{type} eq 'kml' } @$files;
    return () if @kml_files || !@gpx_files;

    return ({
        caption => '',
        thumb_filename => 'route.kml',
        timestamp => '',
        type => 'kml',
    });
}

sub get_original_filename {
    my $self = shift;
    my ($src_dir, $enl_filename, $type) = @_;

    my $orig_prefix;
    if ($type eq 'movie') {
        ($orig_prefix) = ($enl_filename =~ /^(.*).(mp4|mov)$/i);
    } else {
        # Older processed files start with "<NNNNN>-"
        ($orig_prefix) = ($enl_filename =~ /^(?:\d+-)?([-\w~_\(\)]+)-enl.jpg$/);
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
    my $self = shift;
    my ($metadata) = @_;

    my $rating = $metadata->{rating};
    if (! defined $rating) {
        die "Missing rating";
    } elsif ($rating == 1) {
        return 3;
    } elsif ($rating == 2) {
        return 2;
    } elsif ($rating == 3) {
        return 1;
    } else {
        die "Out-of-bounds rating '$rating'. Must be 1, 2, or 3. " . Data::Dumper::Dumper($metadata);
    }
}

sub write_file {
    my $self = shift;
    my ($filename, $content) = @_;

    die "$filename already exists" if -e $filename;

    print "Creating $filename\n";
    my $fh = IO::File->new($filename, "w");
    $fh || die "Can't open '$filename': $!";
    $fh->print($content);
    $fh->close or die "Error writing to '$filename': $!";
}

1;
