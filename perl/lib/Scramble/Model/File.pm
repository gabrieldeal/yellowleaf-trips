package Scramble::Model::File;

use strict;

use Scramble::Model::File::Gps ();
use Scramble::Model::File::Map ();
use Scramble::Model::File::Picture ();

our $FILES_SUBDIR = "pics";

my %TYPE_TO_PACKAGE = (
    gps => "Scramble::Model::File::Gps",
    kml => "Scramble::Model::File::Gps",
    map =>  "Scramble::Model::File::Map",
    movie => "Scramble::Model::File::Picture",
    picture => "Scramble::Model::File::Picture",
);
my %COLLECTIONS = map { ($_, Scramble::Collection->new) } keys %TYPE_TO_PACKAGE;

sub initialize {
    my $self = shift;

    $self->{trip_files_subdir} = File::Basename::basename($self->{trip_files_src_dir});
    $self->{description} = $self->{description} ? ucfirst($self->{description}) : '';
}

sub get_description { $_[0]->{description} }
sub get_filename { $_[0]->{'thumbnail-filename'} }
sub get_id { $_[0]->get_trip_files_src_dir . "|" . $_[0]->get_filename }
sub get_owner { $_[0]->{owner} }
sub get_should_skip_trip { $_[0]->{'skip-trip'} }
sub get_trip_files_src_dir { $_[0]->{trip_files_src_dir} } # FIXME: Does this belong here? It seems like it should just be in Scramble::Build.
sub get_trip_files_subdir { $_[0]->{trip_files_subdir} }
sub get_trip_url { $_[0]->{trip_url} }
sub get_type { $_[0]->{type} }
sub get_url { $_[0]->_get_url($_[0]->get_filename) }
sub set_trip_url { $_[0]->{trip_url} = $_[1] }

# FIXME: Rename 'capture-timestamp' to 'datetime'.
sub get_datetime { $_[0]{'capture-timestamp'} }
# FIXME: rename to get_trip_start_date().  Or remove this and add get_trip().
sub get_date { $_[0]->{date} } # optional for maps that are not for a particular trip
# FIXME: rename to get_date().
sub get_capture_date {
    my $self = shift;

    my $capture_date = $self->{'capture-timestamp'};
    return undef unless defined $capture_date;

    my ($date) = ($capture_date =~ m,^(\d\d\d\d/\d\d/\d\d),);
    return $date;
}

sub _get_url {
    my $self = shift;
    my ($filename) = @_;

    return '' unless $filename;

    return sprintf("../../$FILES_SUBDIR/%s/%s",
                   $self->get_trip_files_subdir,
                   $filename);
}

sub get_full_url {
    my $self = shift;

    return sprintf("https://yellowleaf.org/scramble/$FILES_SUBDIR/%s/%s",
                   $self->get_trip_files_subdir,
                   $self->get_filename);
}

sub cmp_datetime {
    my $self = shift;
    my ($other) = @_;

    return ($self->get_datetime || '') cmp ($other->get_datetime || '');
}

######################################################################

sub get_pictures_collection { $COLLECTIONS{picture} }

sub get_all {
    my @files;

    foreach my $type (keys %COLLECTIONS) {
        push @files, $COLLECTIONS{$type}->get_all;
    }

    return @files;
}

sub read_from_trip {
    my ($trip_files_src_dir, $trip) = @_;

    my $date = $trip->get_start_date();
    my ($year, $month, $day) = Scramble::Time::parse_date($date);

    my $in_chronological_order = $trip->_get_optional('files', 'in-chronological-order');
    if (defined($in_chronological_order) && '' eq $in_chronological_order) {
        die "The 'in-chronological-order' attribute in the 'files' element is empty";
    }

    my @files;
    my $chronological_order = 0;
    foreach my $file_xml (@{ $trip->_get_optional('files', "file") || [] }) {
        next if $file_xml->{skip};

        my $type = normalize_type($file_xml->{type});
        my $pkg = get_package_for_type($type);
        my $params = {
            %$file_xml,
            chronological_order => $chronological_order++,
            in_chronological_order => $in_chronological_order,
            date => "$year/$month/$day",
            trip_files_src_dir => $trip_files_src_dir,
            type => $type,
        };
        my $file = $pkg->new(%$params);

        push @files, $file;
        $COLLECTIONS{$type}->add($file);
    };


    return @files;
}

# FIXME: convert data.
sub normalize_type {
    my ($type) = @_;

    return 'picture' unless $type;

    $type = lc($type);
    return 'gps' if $type eq 'gpx';

    return $type;
}

sub get_package_for_type {
    my ($type) = @_;

    my $pkg = $TYPE_TO_PACKAGE{$type};
    return $pkg if $pkg;

    die "Unrecognized type '$type'";
}

1;
