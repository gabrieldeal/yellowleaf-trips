package Scramble::Model::Trip;

use strict;

use Scramble::Misc ();
use Scramble::Model::Waypoints ();
use Scramble::Model::File ();
use Scramble::Model::Reference ();
use Scramble::Template ();
use Scramble::Time ();

our @ISA = qw(Scramble::Model);

my $g_trip_collection = Scramble::Collection->new();

sub new {
    my ($arg0, $path, $files_src_dir) = @_;

    my $self = Scramble::Model::parse($path);
    if ($self->{'skip'}) {
        print "Skipping $path because 'skip=true'\n";
        return undef;
    }

    bless($self, ref($arg0) || $arg0);

    $self->initialize_waypoints;
    $self->initialize_dates;
    $self->initialize_locations;
    $self->initialize_areas;
    $self->initialize_files($files_src_dir);

    $self->validate;

    return $self;
}

sub initialize_locations {
    my $self = shift;

    my @location_objects;
    foreach my $location_xml ($self->get_locations) {
        my $location = Scramble::Model::Location::find_location(
            name => $location_xml->{name},
            quad => $location_xml->{quad},
            country => $location_xml->{country},
            'include-unvisited' => 1,
            );
        $location->set_have_visited;

        push @location_objects, $location;
    }

    $self->{'location-objects'} = \@location_objects;
}

sub initialize_areas {
    my $self = shift;

    my @areas;
    push @areas, map { $_->get_areas_collection->get_all } $self->get_location_objects;
    push @areas, $self->get_areas_from_xml;
    @areas = Scramble::Misc::dedup(@areas);

    $self->{'areas-object'} = Scramble::Collection->new('objects' => \@areas);
}

sub initialize_files {
    my $self = shift;
    my ($files_src_dir) = @_;

    # FIXME: Move $subdir into trip.xml and move all trip.xml files into the same
    # directory?
    my $subdir = File::Basename::basename(File::Basename::dirname($self->{path}));
    my $trip_files_src_dir = "$files_src_dir/$subdir";
    my @files = Scramble::Model::File::read_from_trip($trip_files_src_dir, $self);
    my $file_collection = Scramble::Collection->new(objects => \@files);

    my @pictures = (
        $file_collection->find('type' => 'picture'),
        $file_collection->find('type' => 'movie'),
        $file_collection->find('type' => 'sound'),
    );
    if (@pictures && $pictures[0]->in_chronological_order) {
        @pictures = sort {
            $a->get_chronological_order <=> $b->get_chronological_order
        } @pictures;
    }
    $self->set_picture_objects([ grep { ! $_->get_should_skip_trip } @pictures]);

    $self->{'map-objects'} = [ $file_collection->find('type' => 'map') ];

    my @kmls = $file_collection->find('type' => 'kml');
    die "Too many KMLs" if @kmls > 1;
    $self->{'kml'} = $kmls[0] if @kmls;

    if ($self->should_show) {
        foreach my $map (@pictures, $self->get_map_objects) {
            $map->set_trip_url($self->get_trip_page_url);
        }
    }
}

sub initialize_waypoints {
    my $self = shift;

    $self->{'waypoints'} = Scramble::Model::Waypoints->new($self->get_filename,
                                                           $self->_get_optional('waypoints'));
}

sub initialize_dates {
    my $self = shift;

    $self->set('start-date', Scramble::Time::normalize_date_string($self->get_start_date_str));

    my $end_date_str = $self->get_end_date_str;
    if (defined $end_date_str) {
        eval { # FIXME: Some waypoints have the time without the date.
            $self->set('end-date', Scramble::Time::normalize_date_string($end_date_str));
        };
    }
}

sub validate {
    my $self = shift;

    my $ndays = $self->get_num_days;
    if ($ndays <= 0 || $ndays >= 1000) {
        die sprintf("Got $ndays days from %s", $self->{path});
    }
}

sub get_id { $_[0]->get_start_date() . "|" . ($_[0]->get_trip_id() || "") }
sub get_trip_id { $_[0]->_get_optional('trip-id') }
sub get_areas_collection { $_[0]->{'areas-object'} }
sub get_waypoints { $_[0]->{'waypoints'} }
sub get_type { $_[0]->_get_optional('type') || 'scramble' }
sub get_end_date { $_[0]->_get_optional('end-date') }
sub get_start_date { $_[0]->_get_optional('start-date') }
sub get_name { $_[0]->_get_required('name') }
sub get_locations { @{ $_[0]->_get_optional('locations', 'location') || [] } }
sub get_location_objects { @{ $_[0]->{'location-objects'} } }
sub get_state { $_[0]->_get_optional('state') || "done" }
sub get_route { $_[0]->_get_optional_content('description') }
sub get_kml { $_[0]->{kml} }
sub get_map_objects { @{ $_[0]->{'map-objects'} } }
sub get_picture_objects { @{ $_[0]->{'picture-objects'} } }
sub set_picture_objects { $_[0]->{'picture-objects'} = $_[1] }
sub skip_spelling { $_[0]->_get_optional('skip-spelling') }

sub should_hide_locations {
    my $self = shift;

    return Scramble::Misc::to_boolean($self->{'should-hide-locations'});
}

sub get_round_trip_distances {
    my $self = shift;

    my $distances = $self->_get_optional('round-trip-distances', 'distance');
    if (!$distances) {
        return undef;
    }

    return [ map {
        if ($_->{kilometers}) {
            my $miles = 0.621371 * $_->{kilometers};
            $_->{miles} = int($miles);
        }

        $_;
    } @$distances ];
}

sub get_end_date_str {
    my $self = shift;

    # FIXME: deprecate the end-date XML attribute in favor of waypoints.
    my $end_date = $self->_get_optional('end-date');
    if ($end_date) {
        return $end_date;
    }

    my $last_waypoint = ($self->get_waypoints->get_waypoints)[-1];
    if ($last_waypoint && $last_waypoint->has_time) {
        return $last_waypoint->get_time;
    }

    return undef;
}

sub get_start_date_str {
    my $self = shift;

    # FIXME: deprecate the start-date XML attribute in favor of waypoints.
    my $start_date = $self->_get_optional('start-date');
    if ($start_date) {
        return $start_date;
    }

    my $first_waypoint = ($self->get_waypoints->get_waypoints)[0];
    if ($first_waypoint && $first_waypoint->has_time) {
        return $first_waypoint->get_time;
    }

    return undef;
}

sub get_filename {
    my $self = shift;
    return $self->_get_required('filename') . ".html";
}

sub get_best_picture_object {
    my $self = shift;

    my $best_picture;
    foreach my $picture ($self->get_picture_objects()) {
        $best_picture = $picture if ! defined $best_picture;
        $best_picture = $picture if $best_picture->get_rating() >= $picture->get_rating();
    }
    return $best_picture;
}

sub get_num_days {
  my $self = shift;

  if (! defined $self->get_end_date()) {
    return 1;
  }

  my ($syear, $smonth, $sday) = Scramble::Time::parse_date($self->get_start_date());
  my ($eyear, $emonth, $eday) = Scramble::Time::parse_date($self->get_end_date());

  my $start = Date::Manip::Date_DaysSince1BC($smonth, $sday, $syear);
  my $end = Date::Manip::Date_DaysSince1BC($emonth, $eday, $eyear);

  return 1 + $end - $start;
}

sub should_show {
    my $self = shift;

    return ! Scramble::Misc::to_boolean($self->_get_optional('should-not-show'))
}

sub get_parsed_start_date {
    my $self = shift;

    my @date = split('/', $self->get_start_date());
    @date == 3 or die sprintf("Bad start date '%s'", $self->get_start_date());
    return @date;
}

sub no_maps {
    my $self = shift;

    return defined $self->_get_optional('maps')
        && ! defined $self->_get_optional('maps', 'map');
}

sub get_maps {
    my $self = shift;

    my @maps;
    push @maps, map { $_->get_reference() } $self->get_map_objects();
    push @maps, @{ $self->_get_optional('maps', 'map') || [] };

    return grep { ! $_->{'skip-map'} } @maps;
}

sub get_trip_page_url {
    my $self = shift;

    return sprintf("../../g/r/%s", $self->get_filename());
}

sub get_references {
    my $self = shift;

    return @{ $self->{'reference-objects'} } if $self->{'reference-objects'};

    my @references = @{ $self->_get_optional('references', 'reference') || [] };
    @references = map { Scramble::Model::Reference::find_or_create($_) } @references;
    @references = grep { !$_->should_skip() } @references;
    @references = sort { Scramble::Model::Reference::cmp($a, $b) } @references;
    @references = Scramble::Misc::dedup(@references);

    $self->{'reference-objects'} = \@references;

    return @references;
}

######################################################################
# statics
######################################################################

sub equals {
    my $self = shift;
    my ($trip) = @_;

    return $trip->get_id() eq $self->get_id();
}

sub cmp_by_duration {
    my ($trip1, $trip2) = @_;

    return $trip1->get_waypoints()->get_car_to_car_delta() <=> $trip2->get_waypoints()->get_car_to_car_delta();
}

sub cmp {
    my ($trip1, $trip2) = @_;

    if ($trip1->get_start_date() ne $trip2->get_start_date()) {
        return $trip1->get_start_date() cmp $trip2->get_start_date();
    }

    if (! defined $trip1->get_trip_id() || ! defined $trip2->get_trip_id()) {
        return defined $trip1->get_trip_id() ? 1 : -1;
    }

    return $trip1->get_trip_id() cmp $trip2->get_trip_id();
}

sub open_specific {
    my ($path_or_dir, $files_src_dir) = @_;

    my $path =  -d $path_or_dir ? "$path_or_dir/trip.xml" : $path_or_dir;
    die "Bad trip location '$path_or_dir'" unless -f $path;

    my $trip = Scramble::Model::Trip->new($path, $files_src_dir);
    $g_trip_collection->add($trip) if defined $trip;
    return $trip;
}

sub open_all {
    my ($files_src_dir, $xml_src_dir) = @_;

    my $glob = "$xml_src_dir/trips/*/trip.xml";
    my @paths = reverse(sort(glob($glob)));
    @paths || die "No trips in $glob";
    foreach my $path (@paths) {
        open_specific($path, $files_src_dir);
    }
}

sub get_all {
    return $g_trip_collection->get_all();
}

sub get_trips_for_location {
    my ($location) = @_;

    my @retval;
    foreach my $trip (get_all()) {
	push @retval, $trip if grep { $location->equals($_) } $trip->get_location_objects();
    }
    return @retval;
}

sub get_shorter_than {
    my ($hours) = @_;

    my @trips;
    foreach my $trip (get_all()) {
        my $minutes = $trip->get_waypoints()->get_car_to_car_delta();
        next unless defined $minutes;
        next unless $minutes < $hours * 60;
        push @trips, $trip;
    }

    return \@trips;
}

######################################################################
# end statics
######################################################################

1;
