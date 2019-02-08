package Scramble::Model::Image;

use strict;

use File::Basename ();
use Scramble::Collection ();
use Scramble::Template ();

# FIXME: It is confusing to use a class named Images to represent GPX, KML, maps and pictures.

my $g_pics_dir = "pics";
my $g_collection = Scramble::Collection->new();

sub new {
    my $arg0 = shift;
    my ($args) = @_;

    my $self = { %$args };
    bless $self, ref($arg0) || $arg0;

    $self->{'type'} = 'picture' unless exists $self->{'type'};
    $self->{trip_files_subdir} = File::Basename::basename($self->{trip_files_src_dir});
    $self->{'chronological-order'} = 0 unless exists $self->{'chronological-order'};
    foreach my $key (qw(trip_files_subdir thumbnail-filename type trip_files_src_dir)) {
        die "Missing '$key': ", Data::Dumper::Dumper($self)
            unless defined $self->{$key};
    }

    $self->{'description'} = $self->{'description'} ? ucfirst($self->{'description'}) : '';

    if (defined $self->{'date'}) {
	$self->{'date'} = Scramble::Time::normalize_date_string($self->{'date'});
    }

    return $self;
}

sub get_id { $_[0]->get_trip_files_src_dir() . "|" . $_[0]->get_filename() }
sub get_chronological_order { $_[0]->{'chronological-order'} }
sub in_chronological_order { $_[0]->{'in-chronological-order'} }
sub get_trip_files_src_dir { $_[0]->{trip_files_src_dir} } # FIXME: Does this belong here? It seems like it should just be in Scramble::Build.
sub get_filename { $_[0]->{'thumbnail-filename'} }
sub get_enlarged_filename { $_[0]->{'large-filename'} }
sub get_trip_files_subdir { $_[0]->{trip_files_subdir} }
sub get_section_name { $_[0]->{'section-name'} }

sub get_date { $_[0]->{'date'} } # optional for maps that are not for a particular trip
sub get_datetime { $_[0]{'capture-timestamp'} }

sub get_description { $_[0]->{'description'} }
sub get_of { $_[0]->{'of'} } # undefined means we don't know. Empty string means it is not of any known location.
sub get_from { $_[0]->{'from'} || '' }
sub get_owner { $_[0]->{'owner'} }
sub get_url { sprintf("../../$g_pics_dir/%s/%s", $_[0]->get_trip_files_subdir(), $_[0]->get_filename()) }
sub get_full_url { sprintf("https://yellowleaf.org/scramble/$g_pics_dir/%s/%s", $_[0]->get_trip_files_subdir(), $_[0]->get_filename()) }
sub get_trip_url { $_[0]->{'trip-url'} }
sub set_trip_url { $_[0]->{'trip-url'} = $_[1] }
sub get_should_skip_trip { $_[0]->{'skip-trip'} }
sub get_type { $_[0]->{'type'} }
sub get_poster { $_[0]->{'poster'} }

sub get_filenames {
    my $self = shift;

    if ($self->get_type eq 'movie' && $self->get_poster) {
        return ($self->get_filename, $self->get_poster);
    }
    if ($self->get_type ne 'picture') {
        return ($self->get_filename);
    }
    if (!$self->get_enlarged_filename) {
        # Old trips like 2005-03-05-Goat-Mtn
        return ($self->get_filename);
    }

    return ($self->get_filename, $self->get_enlarged_filename);
}

sub get_poster_url {
    my $self = shift;

    if (!$self->get_poster) {
        return '';
    }

    return sprintf("../../$g_pics_dir/%s/%s", $self->get_trip_files_subdir(), $self->get_poster());
}

sub get_capture_date {
    my $self = shift;

    my $capture_date = $self->{'capture-timestamp'};
    return undef unless defined $capture_date;

    my ($date) = ($capture_date =~ m,^(\d\d\d\d/\d\d/\d\d),);
    return $date;
}

sub get_rating {
  my $self = shift;

  # Rating v3:
  # 1 - One of my favorites
  # 2 - Pretty
  # 3 - Part of the story

  # Rating v2:
  # 1 - One of my best photos ever.  Very few photos in this category.
  # 2 - Great photo that stands on its own.
  # 3 - Used to distinguish my favorite pics from a trip, where most of the pics in the trip are 3.1.
  # 3.1 - Nice photo, but needs the story to be useful.  Most photos are in this category.
  # 4 - Included only for the story.

  # Rating v1:
  # 1 best
  # 100 worst

  if (defined $self->{rating}) {
    return $self->{rating};
  }
  return 3;
}

sub get_enlarged_img_url {
    my $self = shift;

    return undef unless defined $self->get_enlarged_filename();

    return sprintf("../../$g_pics_dir/%s/%s",
                   $self->get_trip_files_subdir,
                   $self->get_enlarged_filename());
}

sub get_map_reference {
    my $self = shift;

    return { 'name' => $self->get_description(),
	     'URL' => $self->get_url(),
	     'id' => 'routeMap', # used by Scramble::Model::Reference
	     'type' => ($self->{'noroute'} 
			? "Online map"
			: "Online map with route drawn on it"),
	 };
}

sub cmp {
  my ($a, $b) = @_;

  if (! defined $a->get_rating() && ! defined $b->get_rating()) {
    return 0;
  }
  if (! defined $a->get_rating()) {
    return -1;
  }
  if (! defined $b->get_rating()) {
    return 1;
  }
  if ($a->get_rating() == $b->get_rating()) {
    return cmp_date($b, $a); # Newest first
  }
  return $a->get_rating() <=> $b->get_rating();
}

######################################################################
# Statics
######################################################################

sub get_all_images_collection { $g_collection }

sub read_images_from_trip {
    my ($trip_files_src_dir, $trip) = @_;

    my $date = $trip->get_start_date();
    my ($year, $month, $day) = Scramble::Time::parse_date($date);

    my $in_chronological_order = $trip->_get_optional('files', 'in-chronological-order');
    if (defined($in_chronological_order) && '' eq $in_chronological_order) {
	die "images.in-chronological-order is empty";
    }

    my @images;
    my $chronological_order = 0;
    foreach my $image_xml (@{ $trip->_get_optional('files', "file") || [] }) {
        next if $image_xml->{skip};
        push @images, Scramble::Model::Image->new({ date => "$year/$month/$day",
                                                    trip_files_src_dir => $trip_files_src_dir,
                                                    'chronological-order' => $chronological_order++,
                                                    'in-chronological-order' => $in_chronological_order,
                                                    %$image_xml,
                                                  });
    }

    $g_collection->add(@images);
    return @images;
}

sub cmp_date {
  my ($image_a, $image_b) = @_;

  my $date_a = $image_a->get_date();
  my $date_b = $image_b->get_date();
  if ($image_a->get_datetime() && $image_b->get_datetime()) {
      $date_a = $image_a->get_datetime();
      $date_b = $image_b->get_datetime();
  }

  if (! defined $date_a) {
    if (! defined $date_b) {
      return 0;
    } else {
      return -1;
    }
  }
  if (! defined $date_b) {
    return 1;
  }

  return $date_a cmp $date_b;
}

1;
