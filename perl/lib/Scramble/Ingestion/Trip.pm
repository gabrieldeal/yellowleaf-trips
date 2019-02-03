package Scramble::Ingestion::Trip;

use strict;

use Data::Dumper ();
use File::Basename ();
use File::Spec ();
use Geo::Gpx ();
use IO::File ();
use Image::ExifTool ();
use Scramble::Model::Area ();
use Scramble::Model::Location ();
use Scramble::Time ();
use Spreadsheet::Read ();
use XML::Generator ();

# FIXME: Refactor everything

my $g_data_dir = '/home/gabrielx/projects/yellowleaf-trips-data';
my $g_image_dest_basedir = "$g_data_dir/html/pics";
my $g_image_src_basedir = '/media/gabrielx/Backup/Users/Gabriel/projects/yellowleaf-trips/data/gabrielx/reports';

my $xg = XML::Generator->new(escape => 'always',
                             conformance => 'strict',
                             pretty => 4);

sub make_xml {
    my ($image_subdir, $trip_type, $title, $spreadsheet_filename) = @_;

    $ENV{TZ} || die "Set Timezone.  E.g., export TZ='America/Los_Angeles'";
    defined $title or die "Missing arguments: image-subdir trip-type title";

    my $image_src_dir = "$g_image_src_basedir/$image_subdir";
    -d $image_src_dir or die "Non-existant image dir: $image_src_dir";

    my $image_dest_dir = "$g_image_dest_basedir/$image_subdir";
    -d $image_dest_dir or die "Non-existant image dir: $image_dest_dir";

    my ($date) = ($image_subdir =~ /^(\d{4}-\d\d-\d\d)/);
    defined $date or die "Unable to get date from image subdirectory: $image_subdir";

    my %image_data = read_images($image_src_dir);
    my %gps_data = read_gpx(\%image_data);

    copy_misc_images($g_image_dest_basedir);

    ingest_trip_files($image_src_dir, $image_dest_dir, $image_data{files});

    # FIXME: Get rid of $image_subdir and put all trip XML files in trips/.
    my $trip_dir = "$g_data_dir/trips/$image_subdir";
    File::Path::mkpath([$trip_dir], 0, 0755);
    my $trip_xml_file = "$trip_dir/trip.xml";
    if (-e $trip_xml_file) {
        print "$trip_xml_file already exists\n";
    } else {
        my @locations = prompt_for_locations();
        my $sections = read_trip_sections($spreadsheet_filename);
        my $trip_xml = make_trip_xml(date => $date,
                                     title => $title,
                                     trip_type => $trip_type,
                                     locations => \@locations,
                                     sections => $sections,
                                     gps_data => \%gps_data,
                                     image_data => \%image_data,
                                     image_subdir => $image_subdir);
        write_file($trip_xml_file, $trip_xml);
    }

    # geotag($image_data{files});

    my $glob = "$image_src_dir/*";
    my @files = glob($glob);
    if (@files) {
        chmod(0744, @files) || die "Failed to chmod ($!) '$glob'";
    }

    return 0;
}

sub metadata_from_gpx {
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

sub read_gpx {
    my ($images) = @_;

    my @gpx_files = grep { $_->{type} eq 'gps' } @{ $images->{files} };

    return {} unless @gpx_files;

    my %first_gpx = metadata_from_gpx($gpx_files[0]);

    my %last_gpx;
    if (@gpx_files == 1) {
        %last_gpx = %first_gpx;
    } else {
        %last_gpx = metadata_from_gpx($gpx_files[-1]);
    }

    return (
        start => $first_gpx{start},
        end => $last_gpx{end}
        );
}

sub convert_date_time {
    my ($epoch_time) = @_;

    my (undef, $minute, $hour, $day, $mon, $year) = localtime($epoch_time);
    $year += 1900;
    $mon += 1;

    return sprintf("$year/%02d/%02d %02d:%02d", $mon, $day, $hour, $minute);
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
    my @locations;

    my $prompt = "Location (^D to quit): ";
    print $prompt;
    Scramble::Model::Area::open($g_data_dir);
    Scramble::Model::Location::set_data_directory($g_data_dir);
    my %opened_locations;
    while (my $location_name = <STDIN>) {
        my @location_matches;
        my $location_regex = "\Q". join('\E.*\Q', split(/\s+/, $location_name)) . "\E";
        foreach my $location_path (glob("$Scramble::Model::Location::HACK_DIRECTORY/*.xml")) {
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

sub validate_arguments {
    my ($image_dir, $trip_type, $title) = @_;

    defined $title or die "Missing arguments: image-dir trip-type title";
    -d $image_dir or die "Non-existant image dir: $image_dir";

    my ($data_dir, $image_subdir) = ($image_dir =~ m{^(.*)/trips/+([^/]+)/*$});
    defined $image_subdir or die "Bad images dir: $image_dir";

    my ($date) = ($image_subdir =~ /^(\d{4}-\d\d-\d\d)/);
    defined $date or die "Unable to get date from image subdirectory: $image_subdir";
}

# sub geotag {
#     my ($files) = @_;

#     my @gpx_files = grep { $_->{type} eq 'gps'} @$files;
#     return unless @gpx_files;
#     die "Too many GPX files: @gpx_files" unless @gpx_files == 1;
#     my $gpx_file = "$gpx_files[0]{dir}/$gpx_files[0]{enl_filename}";

#     my @image_files = grep { $_->{type} eq 'picture' } @$files;
#     return unless @image_files;
#     my @image_filenames = map { ("$gpx_files[0]{dir}/$_->{thumb_filename}", "$gpx_files[0]{dir}/$_->{enl_filename}") } @image_files;

#     # For example, the following command compensates for image times which
#     # are 1 minute and 20 seconds behind GPS:
#     # exiftool -geosync=+1:20 -geotag a.log DIR
#     warn "Is camera and GPS synced????";
#     my @command = ('exiftool',
# 		   '-verbose',
# 		   '-geotag', $gpx_file,
# 		   @image_filenames);
#     my_system(@command);
# }

sub make_locations_xml {
    my ($locations) = @_;

    my @location_attrs = map {
        {
            name => $_->get_name,
            quad => ($_->get_quad_objects)[0]->get_id,
        }
    } @$locations;

    return $xg->locations(map { $xg->location($_) } @location_attrs);
}

sub make_trip_xml {
    my %args = @_;

    $args{title} =~ s/&/&amp;/g; # It is still the dark ages here.

    my $files_xml = make_files_xml($args{image_data}{files}, $args{date}, $args{sections});
    my $locations_xml = make_locations_xml($args{locations});

    my $start = $args{gps_data}{start} || $args{image_data}{first_timestamp} || '';
    my $end = $args{gps_data}{end} || $args{image_data}{last_timestamp} || '';

    return <<EOT;
<trip filename="$args{image_subdir}"
      start-date="$args{date}"
      name="$args{title}"
      type="$args{trip_type}"
      trip-id="1"
>
    <description />
    <references />

    $locations_xml

    <party size="">
        <member name="Gabriel Deal" type="author"/>
        Lindsay Malone
    </party>

    <round-trip-distances>
        <distance type="foot" miles=""/>
        <distance type="bike" miles=""/>
    </round-trip-distances>

    <waypoints elevation-gain="">
        <waypoint type="ascending"
               location-description=""
               time="$start"
        />
        <waypoint type="break"
               location-description=""
               time="$end"
        />
    </waypoints>

    $files_xml
</trip>
EOT
}

sub prompt_yes_or_no {
    my ($prompt) = @_;
    while (1) {
        print "$prompt\ny/n (y)? ";
        my $answer = <STDIN>;
        chomp $answer;

        return 1 if lc($answer) eq 'y' || $answer eq '';
        return 0 if lc($answer) eq 'n';
    }
}

sub make_files_xml {
    my ($files, $date, $sections) = @_;

    my @file_xmls;
    foreach my $file (sort { $a->{timestamp} cmp $b->{timestamp} } @$files) {
        my %optional_attrs;
        if ($file->{caption} =~ /^(.+)\s+(from|over)\s+(.+)/) {
            my ($of, $term, $from) = ($1, $2, $3);
            $from = '' if $term eq 'over';
            my $question = "\n$file->{caption}\nSet the 'of' and 'from' attributes to the below? ('n' sets it to nothing)\nof: $of\nfrom: $from";
            @optional_attrs{'of', 'from'} = prompt_yes_or_no($question) ? ($of, $from) : ('', '');
        }

        my $section_name;
        if ($file->{timestamp}) {
            my ($year, $mm, $dd) = Scramble::Time::parse_date_and_time($file->{timestamp});
            $section_name = $sections->{"$year/$mm/$dd"};
        }

        push @file_xmls, $xg->file({ %optional_attrs,
                                         'description' => $file->{caption},
                                         'thumbnail-filename' => $file->{thumb_filename},
                                         'large-filename' => $file->{enl_filename},
                                         rating => $file->{rating},
                                         type => $file->{type},
                                         owner => $file->{owner},
                                         'capture-timestamp' => $file->{timestamp},
                                         'section-name' => $section_name,
                                   });
    }

    return $xg->files({ date => $date,
                        'in-chronological-order' => "true",
                        'trip-id' => 1,
                      },
                      @file_xmls);
}

sub make_kml {
    my ($output_dir, @gpx_paths) = @_;

    # gpsconvert chokes on cygwin-style paths.
    my $kml_path = File::Spec->abs2rel("$output_dir/route.kml");
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

sub read_images {
    my ($dir) = @_;

    print "Reading images in $dir...\n";

    -d $dir or die "No such directory '$dir'";
    $dir =~ s{/*$}{};
    my @gpx_filenames = sort(glob "$dir/*.gpx");
    make_kml($dir, @gpx_filenames) if @gpx_filenames;

    my @filenames = @gpx_filenames;
    push @filenames, glob "$dir/*.kml";
    push @filenames, glob "$dir/*-enl\.{jpg,png}";
    push @filenames, glob "$dir/*.{mp4,MP4,MOV,mov}";
    @filenames = sort @filenames;

    my @files;
    foreach my $enl_filename (@filenames) {
        next if $enl_filename =~ /-renc.mp4/i;
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

            my $metadata;
            if ($type eq 'movie') {
                $orig_filename = $enl_filename;
                ($enl_filename) = ($orig_filename =~ /^([-\w_\(\)]+).(mp4|mov)$/i) or die "Failed to parse movie '$enl_filename'";
                $enl_filename .= '-renc.mp4';
                $metadata = get_image_metadata("$dir/$orig_filename");

            } else {
                # Older processed files start with "<NNNNN>-"
                ($orig_filename) = ($enl_filename =~ /^(?:\d+-)?([-\w_\(\)]+)-enl.jpg$/) or die "Failed to parse '$enl_filename'";
                my $orig_filename_glob = get_metadata_filename("$dir/$orig_filename");
                my @orig_filenames = glob($orig_filename_glob);
                @orig_filenames == 1 or die(sprintf("Got %s matches for '$orig_filename_glob': @orig_filenames", scalar(@orig_filenames)));
                
                $metadata = get_image_metadata("$orig_filenames[0]");
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

    my ($first_timestamp, $last_timestamp);
    foreach my $file (@files) {
        $last_timestamp = $file->{timestamp};
        if (! defined $first_timestamp && defined $file->{timestamp}) {
            $first_timestamp = $file->{timestamp};
        }
    }

    return (files => \@files,
	    first_timestamp => $first_timestamp,
	    last_timestamp => $last_timestamp);
}

sub get_metadata_filename {
    my ($path_prefix) = @_;

    my @extensions = map { ($_, uc($_)) } qw(xmp dng);
    foreach my $extension (@extensions) {
        my $path = "$path_prefix.$extension";
        return $path if -e $path;
    }

    die qq(Unable to find metadata file matching "$path_prefix.*");
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

sub process_trip_file {
    my ($dir, $file) = @_;

    if ($file->{type} eq 'movie') {
        reencode_video($dir, $file);
    } elsif ($file->{type} eq 'picture') {
        interlace_image($dir, $file);
    }
}

# Chrome will not display videos from Lindsay's PowerShot without this
# reencoding.
sub reencode_video {
    my ($dir, $file) = @_;

    my $reencoded_video = "$dir/$file->{enl_filename}";
    my @command = ('ffmpeg',
                   '-i', "$dir/$file->{orig_filename}",
                   '-vcodec', 'h264',
                   $reencoded_video);
    if (-e $reencoded_video) {
        print "Reencoded video already exists. Not running @command\n";
        return;
    }

    my_system(@command);
}

sub interlace_image {
    my ($dir, $file) = @_;

    foreach my $file ($file->{thumb_filename}, $file->{enl_filename}) {
        print "\tInterlacing $file\n";
        my_system("mogrify",
                  "-strip", # breaks geotagging
                  "-interlace", "Line",
                  "$dir/$file");
    }
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

sub get_image_metadata {
    my ($file) = @_;

    print "Reading metadata in $file...\n";
    my @tags = qw(Description ImageDescription Rating DateCreated CreateDate Creator Copyright);
    # perl -mImage::ExifTool -mData::Dumper -e "print Data::Dumper::Dumper(Image::ExifTool::ImageInfo('XXXXX.MP4'))"
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

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }

sub my_system {
    my (@command) = @_;

    print "Running @command\n";
    return if 0 == system @command;

    die "Command exited with failure code ($?): @command";
}

sub copy_trip_file {
    my ($file, $src_dir, $dest_dir) = @_;

    next unless defined $file;

    my $source = "$src_dir/$file";
    my $dest = "$dest_dir/$file";
    my $source_mtime = (stat($source))[9] or die "Error getting size '$source': $!";
    my $dest_mtime = (stat($dest))[9];
    if (defined $dest_mtime && $source_mtime < $dest_mtime) {
        return;
    }

    my_system("cp", $source, $dest_dir);
}

sub ingest_trip_files {
    my ($src_dir, $dest_dir, $files) = @_;

    print "Copying trip files...\n";

    File::Path::mkpath([$dest_dir], 0, 0755);

    foreach my $file (@$files) {
        my @file_variants = ($file->{thumb_filename}, $file->{enl_filename});
        my $is_updated = 0;
        foreach my $file_variant (@file_variants) {
            if (copy_trip_file($file_variant, $src_dir, $dest_dir)) {
                $is_updated = 1;
            }
        }

        if ($is_updated) {
            process_trip_file($dest_dir, $file);
        }
    }
}

sub copy_misc_images {
    my ($dest_dir) = @_;

    my @images = glob "images/*.{gif,ico,png,json}";
    @images or die "Unable to find the misc images";

    File::Path::mkpath([$dest_dir], 0, 0755);
    foreach my $image (@images) {
        my_system("cp", $image, "$dest_dir/..");
    }
}

1;
