package Scramble::Model::Location;

use strict;

use Scramble::Model::File ();
use Scramble::Misc ();
use Scramble::Model ();
use Scramble::Model::Area ();

our @ISA = qw(Scramble::Model);
our $LOCATION_XML_SRC_DIRECTORY;

my @g_hidden_locations;
my @g_locations;
my $g_opened = 0;
my %g_check_for_duplicate_ids;

sub in_areas_transitive_closure {
    my $self = shift;

    my @areas;
    foreach my $area ($self->get_areas_collection()->get_all()) {
        push @areas, $area;
        push @areas, $area->in_areas_transitive_closure();
    }

    return @areas;
}

sub new {
    my $arg0 = shift;
    my ($args) = @_;

    my $self = bless({ %$args }, ref($arg0) || $arg0);

    $self->{'have-visited'} = 0;

    $self->initialize_longitude;
    $self->initialize_latitude;
    $self->initialize_areas;
    $self->initialize_quads;
    $self->initialize_state;
    $self->initialize_counties;
    $self->get_areas_collection()->add($self->in_areas_transitive_closure());
    $self->{'country-object'} = $self->get_areas_collection()->find_one('type' => 'country');

    return $self;
}

sub initialize_areas {
    my $self = shift;

    my @areas = $self->get_areas_from_xml;

    $self->{'areas-object'} = Scramble::Collection->new('objects' => \@areas);
}

sub initialize_quads {
    my $self = shift;

    my @quad_objs = $self->get_areas_collection->find('type' => 'USGS quad');

    $self->{'quad-objects'} = [ sort { $a->get_id cmp $b->get_id } @quad_objs ];
    $self->get_areas_collection->add(@quad_objs);
}

sub initialize_state {
    my $self = shift;

    $self->{'state-object'} = (eval { $self->get_areas_collection->find_one('type' => 'state') }
                               || eval { Scramble::Model::Area::get_all->find_one('id' => $self->_get_required('state')) } );
    if ($self->get_state_object) {
      $self->get_areas_collection->add($self->get_state_object);
    }
}

sub initialize_counties {
    my $self = shift;

    my @county_ids;
    if (my @county_objs = $self->get_areas_collection->find('type' => 'county')) {
        push @county_ids, map { $_->get_id } @county_objs;
    }
    $self->{'county-objects'} = [ map { Scramble::Model::Area::get_all->find_one('id' => $_) } @county_ids ];
    $self->get_areas_collection->add($self->get_county_objects);
}

sub initialize_longitude {
    my $self = shift;

    my $lon = $self->_get_optional('coordinates', 'longitude');
    return unless defined $lon;

    $self->set([ 'coordinates', 'longitude' ], 
	       Scramble::Misc::numerify_longitude($lon));
}

sub initialize_latitude {
    my $self = shift;

    my $lat = $self->_get_optional('coordinates', 'latitude');
    return unless defined $lat;

    $self->set([ 'coordinates', 'latitude' ], 
	       Scramble::Misc::numerify_latitude($lat));
}

sub new_objects {
    my ($arg0, $path) = @_;

    my $xml = Scramble::Model::parse($path);

    if (! $xml->{'location'}) {
	return () if $xml->{'incomplete'} || $xml->{'skip'};
	return (Scramble::Model::Location->new($xml));
    }

    my @retval;
    foreach my $location (@{ $xml->{'location'} }) {
	next if $location->{'incomplete'};
	push @retval, Scramble::Model::Location->new({ %$xml, 
                                                       %$location,
                                                       'has-twin' => @{ $xml->{location} } > 1 });
    }

    return @retval;
}

sub get_country_object { $_[0]->{'country-object'} }
sub get_areas_collection { $_[0]->{'areas-object'} }
sub get_quad_objects  { @{ $_[0]->{'quad-objects'} } }
sub get_state_object { $_[0]->{'state-object'} }
sub get_county_objects { @{ $_[0]->{'county-objects'} } }
sub get_type { $_[0]->_get_required('type') }
sub get_description { $_[0]->_get_optional_content('description') }
sub get_elevation { $_[0]->_get_optional('elevation') }
sub get_prominence { $_[0]->_get_optional("prominence") }
sub get_latitude { $_[0]->_get_optional('coordinates', 'latitude') }
sub get_longitude { $_[0]->_get_optional('coordinates', 'longitude') }
sub get_naming_origin { $_[0]->_get_optional('name', 'origin'); }
sub name_is_unique { return ! $_[0]->{'has-twin'} }

sub get_references {
    my $self = shift;

    return @{ $self->{'reference-objects'} } if $self->{'reference-objects'};

    my @references = @{ $self->_get_optional('references', 'reference') || [] };
    @references = map { Scramble::Model::Reference::find_or_create($_) } @references;
    @references = grep { !$_->should_skip() } @references;

    $self->{'reference-objects'} = \@references;

    return @references;
}


sub get_picture_objects {
    my $self = shift;

    # Need to load lazily so this is done after all the trips are loaded.

    return @{ $self->{'picture-objects'} } if $self->{'picture-objects'};

    $self->{'picture-objects'} = [];
    foreach my $regex ($self->get_regex_keys()) {
        foreach my $picture (Scramble::Model::File::get_pictures_collection->get_all) {
	    # FIXME: Should get the USGS quads from the trip or
	    # the pictures and get the location names from the
	    # picture, then do real matching.  This is very broken
	    # for locations like Green Mountain that are on
	    # multiple quads.
            if (defined $picture->get_of()) {
                next unless $picture->get_of() =~ $regex;
            } else {
                next unless $picture->get_description() =~ $regex;
            }
	    
	    my $key = $picture->get_type() . "-objects";
	    push @{ $self->{$key} }, $picture;
	}
    }
    $self->{'picture-objects'} = [ Scramble::Misc::dedup(sort { $a->cmp($b) } @{ $self->{'picture-objects'} }) ];

    return @{ $self->{'picture-objects'} };
}

sub get_is_unofficial_name {
    my $self = shift;

    my $name_xml = $self->_get_optional('name');
    if (ref $name_xml) {
	return $name_xml->{'unofficial-name'};
    }

    return 0;
}

sub get_name {
    my $self = shift;

    my $name = $self->_get_required('name');
    if (! ref $name) {
	return $name;
    }

    return $name->{'value'};
}

sub get_aka_names {
    my $self = shift;

    if (! $self->{'aka-names'}) {
	$self->{'aka-names'} = [];
	foreach my $aka_xml (@{ $self->_get_optional('name', 'AKA') || [] }) {
	    push @{ $self->{'aka-names'} }, $aka_xml->{'name'};
	}
    }

    return @{ $self->{'aka-names'} };
}

# Only guarantee on this string is that it will differ if the location
# objects represent different locations.
# This id shouldn't change over time.
sub get_id { 
    my $self = shift;

    my $id = $self->_get_optional('id');
    $id = defined $id ? "-$id" : '';
    
    return $self->get_name() . $id;
}

sub get_filename { 
    my $self = shift;

    my ($path) = $self->get_id();

    $path =~ s/\#//g;
    $path =~ s/-/--/g;
    $path =~ s/ /-/g;

    return "$path.html";
}

sub have_visited { $_[0]->{'have-visited'} }
sub set_have_visited {
    my $self = shift;

    return if $self->have_visited();

    $self->{'have-visited'} = 1;
    foreach my $area ($self->get_areas_collection()->get_all()) {
	$area->add_location($self);
    }

    @g_hidden_locations = grep { $_ ne $self } @g_hidden_locations;
    push @g_locations, $self;
}

######################################################################
# static methods
######################################################################

sub set_xml_src_directory {
    my ($dir) = @_;

    $LOCATION_XML_SRC_DIRECTORY = "$dir/locations";
}

sub open_specific {
    my (@paths) = @_;

    my @locations;
    foreach my $path (@paths) {
	foreach my $location (Scramble::Model::Location->new_objects($path)) {
	    if (exists $g_check_for_duplicate_ids{$location->get_id()}) {
		die "Duplicate location (add 'id' attr to new location): " . $location->get_id();
	    }
	    $g_check_for_duplicate_ids{$location->get_id()} = 1;

            push @locations, $location;
            push @g_hidden_locations, $location;
	}
    }

    $g_opened = 1;

    return @locations;
}

my $g_collection;
sub get_all {
    if (! $g_collection) {
        $g_collection = Scramble::Collection->new('objects' => [ @g_locations, @g_hidden_locations ]);
    }
    return $g_collection;
}

sub get_visited {
    $g_opened or die "Haven't opened locations yet";
    return @g_locations;
}
sub get_unvisited {
    $g_opened or die "Haven't opened locations yet";
    return @g_hidden_locations;
}

sub equals {
    my $self = shift;
    my ($location) = @_;

    return 1 if $self eq $location;

    my @quads = $location->get_quad_objects();
    my $country = $location->get_country_object();

    return $self->is(name => $location->get_name(),
		     quad => @quads ? $quads[0] : undef,
		     country => $country ? $country : undef);
}
sub is {
    my $self = shift;
    my (%args) = @_;

    defined $args{name} or die "Need name";

    return 0 unless grep { $args{name} eq $_ } ($self->get_name(),
                                                $self->get_aka_names());

    if ($args{quad}) {
      return 0 unless _contains_area($args{quad}, $self->get_quad_objects());
    } elsif($args{country}) {
      return 0 unless _contains_area($args{country}, $self->get_country_object());
    } else {
      die "Need quad or country";
    }

    return 1;
}

sub _contains_area {
  my ($area_name, @areas) = @_;

  foreach my $area (@areas) {
    return 1 if $area->equals($area_name);
  }
  return 0;
}

sub find_location {
    my (%args) = @_;

    # This has two problems:
    # 1. This does not cache negative results.
    # 2. If we load an unvisited peak, try to look it up with include-unvisited false, then we will try to read in the location XML file again.

    my $location = eval { find_cached_location(%args) };
    return $location if $location;

    # Lazily load the location:
    my $name = $args{'name'} || die "Not given name";
    my $path = sprintf("$LOCATION_XML_SRC_DIRECTORY/%s.xml",
                       Scramble::Misc::sanitize_for_filename($name));
    die "Unable to lazily load from $path" unless -f $path;
    open_specific($path);

    return find_cached_location(%args);
}

sub find_cached_location {
    my (%args) = @_;

    my $name = $args{'name'} || die "Not given name";
    my @locations = grep({ $_->is(name => $name,
				  quad => $args{quad},
				  country => $args{country}) } get_visited());
    if ($args{'include-unvisited'}) {
	push @locations, grep({ $_->is(name => $name,
				       quad => $args{quad},
				       country => $args{country} ) } get_unvisited());
    }
    Carp::confess "No match for '$name' in '$args{quad}'" if @locations == 0;
    if (@locations > 1) {
	Carp::confess(sprintf("Too many matches for '%s': %s",
			      Data::Dumper::Dumper(\%args),
			      join(", ", map { $_->get_id() } @locations)));
      }

    return $locations[0];
}

sub get_url {
    my $self = shift;

    return sprintf("../../g/l/%s", $self->get_filename());
}

my %g_location_names_to_objects_mapping;
sub _make_regex {
    my ($regex) = @_;

    $regex =~ s/\+/\\+/g;
    $regex =~ s/\s+/\\s+/g;
    $regex =~ s/\(/\\(/g;
    $regex =~ s/\)/\\)/g;
    if ($regex =~ /^\w/) {
	$regex = '\b' . $regex;
    }
    if ($regex =~ /\w$/) {
	$regex = $regex . '\b';
    }

    return $regex;
}
sub get_regex_keys {
    my $self = shift;

    my @retval;
    foreach my $name ($self->get_name(), $self->get_aka_names()) {
	if ($self->name_is_unique()) {
	    my $regex = _make_regex($name);
	    push @retval, $regex;
	}
	foreach my $quad ($self->get_quad_objects()) {
	    push @retval, _make_regex(sprintf("%s (%s quad)", 
					      $name,
					      $quad->get_id()));
	}
    }

    return @retval;
}

1;
