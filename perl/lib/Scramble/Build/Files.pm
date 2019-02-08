package Scramble::Build::Files;

# Copies:
#   favicons, RSS PNG, manifest.json
#   trip images & videos
#   trip GPX files
# Interlaces images
# Reencodes videos

use strict;

use Scramble::Misc qw(my_system);

sub new {
    my ($arg0, %args) = @_;

    my @fields = qw(
        code_dir
        images
        output_dir
    );
    my $self = { map { $_ => $args{$_} } @fields };
    bless($self, ref($arg0) || $arg0);

    return $self;
}

sub build {
    my $self = shift;

    $self->copy_misc_images;
    $self->copy_and_process_trip_files;
    $self->create_kmls;
}

sub copy {
    my $self = shift;
    my (%args) = @_;

    File::Path::mkpath([$args{dest_dir}], 0, 0755);

    my $source = "$args{src_dir}/$args{filename}";
    my $dest = "$args{dest_dir}/$args{filename}";

    # Cannot check size because only the destination images are interlaced.
    my $source_mtime = (stat($source))[9] or die "Error getting mtime '$source': $!";
    my $dest_mtime = (stat($dest))[9];

    if (defined $dest_mtime && $source_mtime < $dest_mtime) {
        return 0;
    }

    my_system("cp", $source, $args{dest_dir});

    return 1;
}

sub copy_misc_images {
    my $self = shift;

    my $glob = "$self->{code_dir}/images/*.{gif,ico,png,json}";

    my @image_paths = glob $glob;
    @image_paths or die "Unable to find $glob";

    foreach my $image_path (@image_paths) {
        my $src_dir = File::Basename::dirname($image_path);
        my $image_filename = File::Basename::basename($image_path);
        $self->copy(src_dir => $src_dir,
                    dest_dir => $self->{output_dir},
                    filename => $image_filename);
    }
}

# Doing the copy & process together so we don't copy everything, then
# fail halfway through the processing, and end up in a screwed up
# state.
sub copy_and_process_trip_files {
    my $self = shift;

    print "Copying trip files...\n";

    foreach my $image (@{ $self->{images} }) {
        my $is_updated = 0;
        foreach my $filename ($image->get_filenames) {
            next unless $filename; # For old trips like 2013-11-17-nason

            my $src_path = $image->get_files_src_dir . "/$filename";
            next if $image->get_type eq 'kml' && ! -f $src_path;

            if ($self->copy(src_dir => $image->get_files_src_dir,
                            dest_dir => $self->get_trip_files_dest_dir($image),
                            filename => $filename))
            {
                $is_updated = 1;
            }
        }

        if ($is_updated) {
            $self->process_trip_file($image);
        }
    }
}

sub process_trip_file {
    my $self = shift;
    my ($image) = @_;

    if ($image->get_type eq 'movie') {
        $self->reencode_trip_video($image);
    } elsif ($image->get_type eq 'picture') {
        $self->interlace_trip_image($image);
    }
}

# Chrome will not display videos from Lindsay's PowerShot without this
# reencoding.
sub reencode_trip_video {
    my $self = shift;
    my ($image) = @_;

    my $dest_video = sprintf("%s/%s",
                             $self->get_trip_files_dest_dir($image),
                             $image->get_filename);

    # FIXME: duplicate from Scramble::Build::Trip
    my $src_filename = $image->get_filename;
    $src_filename =~ s/-renc\.(...)$/.$1/;

    my $src_video = sprintf("%s/%s",
                            $image->get_files_src_dir,
                            $src_filename);

    my @command = ('ffmpeg',
                   '-i', $src_filename,
                   '-vcodec', 'h264',
                   $dest_video);
    if (-e $dest_video) {
        print "Reencoded video already exists. Not running @command\n";
        return;
    }

    my_system(@command);
}

sub interlace_trip_image {
    my $self = shift;
    my ($image) = @_;

    my $trip_files_dest_dir = $self->get_trip_files_dest_dir($image);

    foreach my $filename ($image->get_filenames) {
        my_system("mogrify",
                  "-strip", # breaks geotagging
                  "-interlace", "Line",
                  "$trip_files_dest_dir/$filename");
    }
}

sub get_trip_files_dest_dir {
    my $self = shift;
    my ($image) = @_;

    return $self->{output_dir} . '/' . $image->get_trip_files_subdir;
}

sub create_kmls {
    my $self = shift;

    foreach my $kml (grep { $_->{type} eq 'kml' } @{ $self->{images} }) {
        $self->create_kml($kml);
    }
}

sub create_kml {
    my $self = shift;
    my ($kml) = @_;

    my $kml_path = $self->get_trip_files_dest_dir($kml) . "/" . $kml->get_filename;
    return if -f $kml_path;

    my $gpx_src_glob = $kml->get_files_src_dir . "/*.gpx";
    my @gpx_paths = sort(glob $gpx_src_glob);
    @gpx_paths > 0 or die "No GPX files at $gpx_src_glob";

    my $gpsconvert = "$self->{code_dir}/bin/gpsconvert";

    my_system($gpsconvert,
              '--no-waypoints',
              '--simplify',
              @gpx_paths,
              '-o', $kml_path);
}

1;
