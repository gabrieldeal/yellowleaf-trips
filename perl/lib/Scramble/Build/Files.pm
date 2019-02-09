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
        files
        output_dir
    );
    my $self = { map { $_ => $args{$_} } @fields };
    bless($self, ref($arg0) || $arg0);

    return $self;
}

sub build {
    my $self = shift;

    $self->copy_misc_files;
    $self->copy_and_process_trip_files;
    $self->create_kmls;
}

sub copy {
    my $self = shift;
    my (%args) = @_;

    File::Path::mkpath([$args{dest_dir}], 0, 0755);

    my $source = "$args{src_dir}/$args{filename}";
    my $dest = "$args{dest_dir}/$args{filename}";

    # Cannot check size because only the destination pictures are interlaced.
    my $source_mtime = (stat($source))[9] or die "Error getting mtime '$source': $!";
    my $dest_mtime = (stat($dest))[9];

    if (defined $dest_mtime && $source_mtime < $dest_mtime) {
        return 0;
    }

    my_system("cp", $source, $args{dest_dir});

    return 1;
}

sub copy_misc_files {
    my $self = shift;

    my $glob = "$self->{code_dir}/images/*.{gif,ico,png,json}";

    my @paths = glob $glob;
    @paths or die "Unable to find $glob";

    foreach my $path (@paths) {
        my $src_dir = File::Basename::dirname($path);
        my $filename = File::Basename::basename($path);
        $self->copy(src_dir => $src_dir,
                    dest_dir => $self->{output_dir},
                    filename => $filename);
    }
}

# Doing the copy & process together so we don't copy everything, then
# fail halfway through the processing, and end up in a screwed up
# state.
sub copy_and_process_trip_files {
    my $self = shift;

    print "Copying trip files...\n";

    foreach my $file (@{ $self->{files} }) {
        my $is_updated = 0;
        foreach my $filename ($file->get_filenames) {
            next unless $filename; # For old trips like 2013-11-17-nason

            my $src_path = $file->get_trip_files_src_dir . "/$filename";
            next if $file->get_type eq 'kml' && ! -f $src_path;

            if ($self->copy(src_dir => $file->get_trip_files_src_dir,
                            dest_dir => $self->get_trip_files_dest_dir($file),
                            filename => $filename))
            {
                $is_updated = 1;
            }
        }

        if ($is_updated) {
            $self->process_trip_file($file);
        }
    }
}

sub process_trip_file {
    my $self = shift;
    my ($file) = @_;

    if ($file->get_type eq 'movie') {
        $self->reencode_trip_video($file);
    } elsif ($file->get_type eq 'picture') {
        $self->interlace_trip_picture($file);
    }
}

# Chrome will not display videos from Lindsay's PowerShot without this
# reencoding.
sub reencode_trip_video {
    my $self = shift;
    my ($file) = @_;

    my $dest_video = sprintf("%s/%s",
                             $self->get_trip_files_dest_dir($file),
                             $file->get_filename);

    # FIXME: duplicate from Scramble::Build::Trip
    my $src_filename = $file->get_filename;
    $src_filename =~ s/-renc\.(...)$/.$1/;

    my $src_video = sprintf("%s/%s",
                            $file->get_trip_files_src_dir,
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

sub interlace_trip_picture {
    my $self = shift;
    my ($picture) = @_;

    my $trip_files_dest_dir = $self->get_trip_files_dest_dir($picture);

    foreach my $filename ($picture->get_filenames) {
        my_system("mogrify",
                  "-strip", # breaks geotagging
                  "-interlace", "Line",
                  "$trip_files_dest_dir/$filename");
    }
}

sub get_trip_files_dest_dir {
    my $self = shift;
    my ($file) = @_;

    return $self->{output_dir} . '/' . $file->get_trip_files_subdir;
}

sub create_kmls {
    my $self = shift;

    foreach my $kml (grep { $_->{type} eq 'kml' } @{ $self->{files} }) {
        $self->create_kml($kml);
    }
}

sub create_kml {
    my $self = shift;
    my ($kml) = @_;

    my $kml_path = $self->get_trip_files_dest_dir($kml) . "/" . $kml->get_filename;
    return if -f $kml_path;

    my $gpx_src_glob = $kml->get_trip_files_src_dir . "/*.gpx";
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
