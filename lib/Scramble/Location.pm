package Scramble::Location;

use strict;

use Math::Trig ();
use Scramble::Image ();
use Scramble::Misc ();
use Scramble::XML ();
use Scramble::Area ();
use Geo::Coordinates::UTM ();

our @ISA = qw(Scramble::XML);

my @g_hidden_locations;
my @g_locations;
my $g_opened = 0;
my $g_avvy_elev_threshold = 1500;
my $g_miles_distance_threshold = 5;

sub image_sort($$) {
    my ($l, $r) = @_;
    # not all images have ratings.
    return 1 unless defined $l->get_rating();
    return -1 unless defined $r->get_rating();
    return $l->get_rating() <=> $r->get_rating();
}

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
    my (%args) = @_;

    my $self = bless({ %args }, ref($arg0) || $arg0);

    $self->{'have-visited'} = 0;
    {
	my @areas = $self->get_areas_from_xml();
	$self->{'areas-object'} = Scramble::Collection->new('objects' => \@areas);
    }

    {
	my $quad_name = $self->_get_optional('quad');
	my @quad_objs;
	if ($quad_name) {
	    @quad_objs = Scramble::Area->get_all()->find_one('id' => $quad_name,
							     'type' => 'USGS quad');
	} else {
	    @quad_objs = $self->get_areas_collection()->find('type' => 'USGS quad');
	}

	$self->{'quad-objects'} = [ sort { $a->get_id() cmp $b->get_id() } @quad_objs ];
	$self->get_areas_collection()->add(@quad_objs);
    }

    $self->{'state-object'} = (eval { $self->get_areas_collection()->find_one('type' => 'state') } 
			       || eval { Scramble::Area::get_all()->find_one('id' => $self->_get_required('state')) } );
    if ($self->get_state_object()) {
      $self->get_areas_collection()->add($self->get_state_object());
    }

    {
	my @county_ids;
	if (my $county_ids = ($self->_get_optional('county') 
			      || $self->_get_optional('counties')))
	{
	    push @county_ids, split(/,\s+/, $county_ids);
	} elsif (my @county_objs = $self->get_areas_collection()->find('type' => 'county')) {
	    push @county_ids, map { $_->get_id() } @county_objs;
	}
	$self->{'county-ids'} = \@county_ids;
	$self->{'county-objects'} = [ map { Scramble::Area::get_all()->find_one('id' => $_) } @county_ids ];
	$self->get_areas_collection()->add($self->get_county_objects());
    }

    $self->get_areas_collection()->add($self->in_areas_transitive_closure());

    $self->{'country-object'} = $self->get_areas_collection()->find_one('type' => 'country');

    if (Scramble::Image::get_all_images_collection()) {
	$self->{'map-objects'} = [];
	$self->{'picture-objects'} = [];
	foreach my $regex ($self->get_regex_keys()) {
	    foreach my $image (Scramble::Image::get_all_images_collection()->get_all()) {
                # FIXME: Should get the USGS quads from the report or
                # the images and get the location names from the
                # image, then do real matching.  This is very broken
                # for locations like Green Mountain that are on
                # multiple quads.
                if (! (($image->get_of() && $image->get_of() =~ $regex)
                       || $image->get_title() =~ $regex))
                {
                    next;
                }
		my $key = $image->get_type() . "-objects";
		push @{ $self->{$key} }, $image;
	    }
	}
        $self->{'picture-objects'} = [ sort { $a->cmp($b) } @{ $self->{'picture-objects'} } ];
    }

    $self->_get_longitude();
    $self->_get_latitude();
    $self->_get_UTM_from_lat_lon();
#    if (! defined $self->get_latitude() && 'peak' eq $self->get_type()) {
#	die sprintf("'%s' is missing coordinates\n", $self->get_name());
#    }

    return $self;
}
sub _get_longitude {
    my $self = shift;

    my $lon = $self->_get_optional('coordinates', 'longitude');
    return unless defined $lon;

    $self->set([ 'coordinates', 'longitude' ], 
	       Scramble::Misc::numerify_longitude($lon));
}
sub _get_latitude {
    my $self = shift;

    my $lat = $self->_get_optional('coordinates', 'latitude');
    return unless defined $lat;

    $self->set([ 'coordinates', 'latitude' ], 
	       Scramble::Misc::numerify_latitude($lat));
}
sub _datum_translate {
    my ($datum) = @_;

    $datum = "Clarke 1866" if uc($datum) eq 'NAD27';
    $datum = "GRS 1980" if uc($datum) eq 'NAD83'; # ?

    return $datum;
}
sub _get_UTM_from_lat_lon {
    my $self = shift;

    return unless defined $self->get_latitude();

    my ($zone, $easting, $northing) = Geo::Coordinates::UTM::latlon_to_utm(_datum_translate($self->get_map_datum()),
									   $self->get_latitude(), 
									   $self->get_longitude());
    $easting = int($easting + .5);
    $northing = int($northing + .5);

    $self->set([ 'coordinates', 'zone' ], $zone);
    $self->set([ 'coordinates', 'easting' ], $easting);
    $self->set([ 'coordinates', 'northing' ], $northing);
}

sub new_objects {
    my ($arg0, $path) = @_;

    my $xml = Scramble::XML::parse($path);

    if (! $xml->{'location'}) {
	return () if $xml->{'incomplete'} || $xml->{'skip'};
	return (Scramble::Location->new('xml' => $xml));
    }

    my @retval;
    foreach my $location (@{ $xml->{'location'} }) {
	next if $location->{'incomplete'};
	push @retval, Scramble::Location->new('xml' => { %$xml, 
							 %$location },
					      'has-twin' => 1);
    }

    return @retval;
}

sub name_is_unique { return ! $_[0]->{'has-twin'} }

sub is_in_USA() { $_[0]->get_country_object()->get_name() eq 'USA'; }
sub get_country_object { $_[0]->{'country-object'} }

sub is_high_point {
    return ($_[0]->get_type() eq 'peak'
            || $_[0]->get_type() eq 'ridge');
}

sub get_type { $_[0]->_get_required('type') }
sub get_path { $_[0]->_get_required('path') }
sub get_locations { @{ $_[0]->_get_optional('locations', 'location') || [] } }
sub get_references { @{ $_[0]->_get_optional('references', 'reference') || [] } }
sub get_description { $_[0]->_get_optional_content('description') }
sub get_elevation { $_[0]->_get_optional('elevation') }
sub get_prominence { $_[0]->_get_optional("prominence") }
sub get_min_elevation { $_[0]->_get_optional('min-elevation') }
sub get_max_elevation { $_[0]->_get_optional('max-elevation') }
sub get_latitude { $_[0]->_get_optional('coordinates', 'latitude') }
sub get_longitude { $_[0]->_get_optional('coordinates', 'longitude') }
sub get_UTM_zone { $_[0]->_get_optional('coordinates', 'zone') }
sub get_UTM_easting { $_[0]->_get_optional('coordinates', 'easting') }
sub get_UTM_northing { $_[0]->_get_optional('coordinates', 'northing') }
sub get_is_driving_location { $_[0]->_get_optional('is-driving-location') }
sub get_is_road { $_[0]->_get_optional('is-road') }
sub get_naming_origin { $_[0]->_get_optional('name', 'origin'); }

sub get_is_unofficial_name {
    my $self = shift;

    my $value = $self->_get_optional('unofficial-name');
    if (defined $value) {
	return $value;
    }

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

sub get_map_datum { 
    my $self = shift;

    my $datum = $self->_get_optional('coordinates', 'datum');
    return undef unless defined $datum;
    return uc($datum);
}

sub get_next_nearest_peak { $_[0]->_get_optional("next-nearest") }
sub get_next_nearest_peak_object { 
    my $self = shift;

    # This has to be done lazily.
    if (! exists $self->{'next-nearest-peak-object'} && $self->get_next_nearest_peak()) {
	$self->{'next-nearest-peak-object'} = eval { find_location('name' => $self->get_next_nearest_peak()) };
    }

    return $self->{'next-nearest-peak-object'};
}

sub get_formatted_elevation {
    my $self = shift;
    return $self->_get_formatted_elevation(\&Scramble::Misc::format_elevation);
}
sub get_short_formatted_elevation {
    my $self = shift;
    return $self->_get_formatted_elevation(\&Scramble::Misc::format_elevation_short);
}
sub _get_formatted_elevation {
    my $self = shift;
    my ($format_func) = @_;

    if ($self->get_elevation()) {
	return $format_func->($self->get_elevation());
    } elsif ($self->get_min_elevation()) {
	return sprintf("%s to %s",
		       $format_func->($self->get_min_elevation()),
		       $format_func->($self->get_max_elevation()));
    }

    return undef;
}

sub get_UTM_coordinates_html {
    my $self = shift;

    return unless defined $self->get_UTM_easting();

    return sprintf("%s %sE %sN (%s)",
		   $self->get_UTM_zone(),
		   $self->get_UTM_easting(),
		   $self->get_UTM_northing(),
		   $self->get_map_datum());
}

sub get_aka_names { 
    my $self = shift;

    my @names;

    foreach my $aka_xml (@{ $self->_get_optional('name', 'AKA') || [] }) {
	push @names, $aka_xml->{'name'};
    }

    my $names = $self->_get_optional('AKA');
    return @names unless $names;

    if ($names =~ /;/) {
	push @names, split(/;\s*/, $names);
    } else {
	push @names, split(/,\s*/, $names);
    }

    return @names;
}
sub get_aka_names_html {
    my $self = shift;

    if (grep /,/, $self->get_aka_names()) {
	return join("; ", $self->get_aka_names());
    } else {
	return join(", ", $self->get_aka_names());
    }
}

sub get_areas_collection { $_[0]->{'areas-object'} }

sub get_quad_objects  { @{ $_[0]->{'quad-objects'} } }

sub get_state_object { $_[0]->{'state-object'} }
sub get_state_name { $_[0]->get_state_object()->get_name() }
sub get_state_abbreviation { $_[0]->get_state_object() ? $_[0]->get_state_object()->get_id() : undef }

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

    return sprintf("%s.html", Scramble::Misc::make_location_into_path($self->get_id()));
}


sub get_maps { 
    my $self = shift;

    my @maps;

    push @maps, map { $_->get_map_reference() } $self->get_map_objects();

    if ($self->get_google_maps_url()) {
	push @maps, { 'type' => sprintf("Satellite photo of %s",
                                        $self->get_name()),
		      'URL' => $self->get_google_maps_url(),
		      'id' => "googleMaps", # used by Scramble::Reference
		      'name' => "Google Maps",
		  };
    }
    if ($self->get_my_google_maps_url()) {
	push @maps, { 'type' => sprintf("Online USGS map of %s",
                                        $self->get_name()),
		      'URL' => $self->get_my_google_maps_url(),
		      'id' => "myGoogleMaps", # used by Scramble::Reference
		      'name' => "Google Maps",
		  };
    }
#     if ($self->get_topozone_url()) {
# 	push @maps, { 'type' => sprintf("Online USGS map of %s", $self->get_name()),
# 		      'URL' => $self->get_topozone_url(),
# 		      'id' => "topozoneMap", # used by Scramble::Reference
# 		      'name' => "TopoZone.com",
# 		  };
#     }
#     if ($self->get_terraserver_url()) {
# 	push @maps, { 'type' => sprintf("Online USGS map of %s", $self->get_name()),
# 		      'URL' => $self->get_terraserver_url(),
# 		      'id' => "terraserverMap", # used by Scramble::Reference
# 		      'name' => "TerraServer",
# 		  };
#     }
    if (($self->get_type() eq 'trailhead' 
	 || $self->get_is_driving_location())
	&& defined $self->get_latitude())
    {
	push @maps, { 'type' => sprintf("Online road map of %s", $self->get_name()),
		      'URL' => Scramble::Misc::get_MSN_maps_url($self->get_latitude(), $self->get_longitude(), $self->get_map_datum()),
		      'id' => "MSN Maps", # used by Scramble::Reference
		      'name' => "maps.msn.com",
		  };
    }

    foreach my $quad ($self->get_quad_objects()) {
	push @maps, { 'id' => 'USGS quad',
		      'is-driving-location' => $self->get_is_driving_location(),
		      'name' => $quad->get_id(),
		  };
    }
    push @maps, @{ $self->_get_optional('maps', 'map') || [] };

    return @maps;
}

sub get_maps_html {
    my $self = shift;

    my @map_htmls = Scramble::Reference::get_map_htmls([ $self->get_maps() ]);
    return Scramble::Misc::make_optional_line("<h2>Maps</h2> <ul><li>%s</li></ul>",
					      @map_htmls ? join("</li>\n<li>", @map_htmls) : undef);

}

# sub get_topozone_url {
#     my $self = shift;

#     return undef unless $self->is_in_USA();
#     return undef unless $self->get_latitude();
#     return Scramble::Misc::get_topozone_url($self->get_latitude(),
# 					    $self->get_longitude(),
# 					    $self->get_map_datum());
# }

sub get_google_maps_url {
    my $self = shift;

    return undef unless $self->get_latitude();
    return Scramble::Misc::get_google_maps_url($self->get_latitude(),
                                               $self->get_longitude(),
                                               $self->get_map_datum());
}

sub get_my_google_maps_url {
    my $self = shift;

    return undef unless $self->get_latitude();
    return Scramble::Misc::get_my_google_maps_url($self->get_latitude(),
                                                  $self->get_longitude(),
                                                  $self->get_map_datum());
}

sub get_county_objects { @{ $_[0]->{'county-objects'} } }
sub get_county_ids { @{ $_[0]->{'county-ids'} } }
sub get_county_names { 
    my $self = shift;
    return map { $_->get_name() } $self->get_county_objects();
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

sub open_all {
    my %check_for_duplicate_ids;
    foreach my $path (sort glob("data/locations/*.xml")) {
	foreach my $location (Scramble::Location->new_objects($path)) {
	    push @g_hidden_locations, $location;

	    if (exists $check_for_duplicate_ids{$location->get_id()}) {
		die "Duplicate location (add 'id' attr to new location): " . $location->get_id();
	    }
	    $check_for_duplicate_ids{$location->get_id()} = 1;
	}
    }

    $g_opened = 1;
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

    return 0 unless $args{name} ~~ [$self->get_name(), $self->get_aka_names()]; # ~~ is smart match

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

    my $name = $args{'name'} || die "Not given name";
    my @locations = grep({ $_->is(name => $name,
				  quad => $args{quad},
				  country => $args{country}) } get_visited());
    if ($args{'include-unvisited'}) {
	push @locations, grep({ $_->is(name => $name,
				       quad => $args{quad},
				       country => $args{country} ) } get_unvisited());
    }

    Carp::confess "No match for '$name'" if @locations == 0;
    if (@locations > 1) {
	Carp::confess(sprintf("Too many matches for '%s': %s",
			      Data::Dumper::Dumper(\%args),
			      join(", ", map { $_->get_id() } @locations)));
      }

    return $locations[0];
}

sub get_counties_html {
    my $self = shift;

    my @htmls = map { $_->get_short_link_html() } $self->get_county_objects();

    return @htmls ? join(", ", @htmls) : undef;
}

sub get_state_html {
    my $self = shift;

    if (! $self->get_state_object()) {
      return undef;
    }
    return $self->get_state_object()->get_short_link_html();
}

sub get_areas_html {
    my $self = shift;

    my @areas = $self->get_areas_collection()->get_all();
    if (! @areas) {
	return '';
    }

    return Scramble::Misc::make_optional_line("<h2>Inside of</h2> <ul><li>%s</li></ul>", 
					      join("</li><li>",
						   Scramble::Misc::get_abbreviated_name_links(@areas)));
}

sub make_nearby_locations_html {
    my $self = shift;

    my @nearby = $self->find_nearby_peaks($g_miles_distance_threshold);
    return '' unless @nearby;

    @nearby = sort { $a->{'miles'} <=> $b->{'miles'} } @nearby;

    my @link_htmls = map { $_->{'location'}->get_link_html() } @nearby;
    return sprintf("<h2>Nearby Peaks</h2> <ul><li>%s</li></ul>",
		   join("</li><li>", @link_htmls));
}

sub get_quads_html {
    my $self = shift;

    return '' unless $self->get_quad_objects();
    my $links = join(", ", map { $_->get_short_link_html } $self->get_quad_objects());
    my $title = sprintf("USGS %s", Scramble::Misc::pluralize(scalar($self->get_quad_objects()),
							     "quad"));
    return Scramble::Misc::make_colon_line($title, $links);
}

# sub get_topozone_html {
#     my $self = shift;

#     my $url = $self->get_topozone_url();
#     return '' unless $url;

#     return Scramble::Misc::make_colon_line("Online topo map",
#                                            qq(<a href="$url">TopoZone.com</a>));
# }

sub get_embedded_google_map_html {
    my $self = shift;

    return Scramble::Misc::get_multi_point_embedded_google_map_html([ $self ]);
}

# sub get_terraserver_html {
#     my $self = shift;

#     return '' unless $self->is_in_USA();

#     return Scramble::Misc::get_terraserver_html($self->get_UTM_easting(),
#                                                 $self->get_UTM_northing(),
#                                                 $self->get_UTM_zone());
# }

# sub get_terraserver_url {
#     my $self = shift;

#     return '' unless $self->is_in_USA();

#     return Scramble::Misc::get_terraserver_url($self->get_UTM_easting(),
#                                                $self->get_UTM_northing(),
#                                                $self->get_UTM_zone());
# }

sub make_page_html {
    my $self = shift;

    1;# this keeps lame font-mode from screwing up indentation.
    Scramble::Logger::verbose(sprintf("Rendering HTML for '%s'\n", 
                                      $self->get_name()));

    my $location_name_note = ($self->get_is_unofficial_name()
			      ? " (unofficial name)"
			      : '');
    my $prominence = Scramble::Misc::make_optional_line(qq(<b><a href="http://www.peaklist.org/theory/theory.html">Clean Prominence</a>:</b> %s<br>),
							\&Scramble::Misc::format_elevation,
							$self->get_prominence());
    my $lists_html = Scramble::Misc::make_optional_line("<h2>In These Peak Lists</h2> %s",
							Scramble::List::make_lists_html($self));
    my $directions_html = Scramble::Misc::make_optional_line("<h2>Driving Directions</h2> %s",
							     $self->get_driving_directions_html());
    my $quad_links = $self->get_quads_html();
    my $county_html = Scramble::Misc::make_optional_line("<b>County:</b> %s<br>",
							 $self->get_counties_html());
    my $elevation = Scramble::Misc::make_colon_line("Elevation", $self->get_formatted_elevation());
    my $utm_html = Scramble::Misc::make_colon_line("UTM",
						   $self->get_UTM_coordinates_html());
    my $description = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("<h2>Description</h2>%s",
										 $self->get_description()));
    my $reports_html = Scramble::Misc::make_optional_line("<h2>Trip Reports and References</h2> %s",
							  get_reports_for_location_html($self));
    my $maps_html = $self->get_maps_html($self);
    my $recognizable_areas_html = $self->get_recognizable_areas_html();

    my $state_html = Scramble::Misc::make_colon_line("State", $self->get_state_html());

    my $aka_html = Scramble::Misc::make_optional_line("<b>AKA:</b> %s<br>",
						      $self->get_aka_names_html());
    my $title = sprintf("Location: %s", $self->get_name());
    my $naming_origin = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("<h2>Name origin</h2> %s",
                                                                                   $self->get_naming_origin()));
    my $locations_nearby_html = $self->make_nearby_locations_html();

    my $next_higher_peak = '';
    if ($self->get_next_nearest_peak()) {
	my $peak = ($self->get_next_nearest_peak_object()
		    ? $self->get_next_nearest_peak_object()->get_short_link_html()
		    : $self->get_next_nearest_peak());
	$next_higher_peak = Scramble::Misc::make_colon_line("Next Higher Peak", 
							    $peak);
    }

#my $terraserver_html = $self->get_terraserver_html();

    my $text_html = <<EOT;
$aka_html
$elevation
$prominence
$next_higher_peak
$state_html
$county_html
$recognizable_areas_html
$quad_links
$utm_html

$reports_html
$description
$naming_origin
$directions_html
$maps_html
$lists_html
$locations_nearby_html
EOT

    my $cells_html = Scramble::Misc::render_images_into_flow('htmls' => [ $text_html, $self->get_embedded_google_map_html() ],
							     'images' => [ $self->get_picture_objects() ]);

    my $html = <<EOT;
<h1>$title$location_name_note</h1>
$cells_html
EOT

    Scramble::Misc::create(sprintf("l/%s", $self->get_filename()),
			   Scramble::Misc::make_1_column_page(title => $title,
							      'include-header' => 1,
							      html => $html,
							      'enable-google-ad' => 0,
							      'no-add-picture' => 1,
                                                              'enable-embedded-google-map' => $Scramble::Misc::gEnableEmbeddedGoogleMap));
}

sub make_locations {
    my @locations;
    foreach my $location_xml (get_visited(), get_unvisited()) {
	$location_xml->make_page_html();
    }
}

sub get_link_html {
    my $self = shift;

    my $picture_icon_html = ($self->has_pictures() 
			     ? " " . Scramble::Misc::get_pictures_img_html()
			     : '');
    my $elevation = "";
    if ($self->get_short_formatted_elevation()) {
        $elevation = "(" . $self->get_short_formatted_elevation() . ")";
    }
    return sprintf("%s %s%s",
		   $self->get_short_link_html(),
                   $elevation,
		   $picture_icon_html);
}

sub get_short_link_html {
    my $self = shift;
    my ($name) = @_;

    $name = $self->get_name() unless defined $name;

    sprintf(qq(<a href="../../g/l/%s">%s</a>),
	    $self->get_filename(),
	    $name);
}

# sub get_weather_forecast_link_html {
#     my $self = shift;

#     return join("</li><li>", reverse sort $self->get_weather_forecast_link_htmls());
# }
# sub get_weather_forecast_link_htmls {
#     my $self = shift;

#     return () unless $self->is_in_USA();

#     my %links;

#     if (defined $self->get_latitude()) {
#         my $noaa_url = Scramble::Misc::get_noaa_forecast_url($self->get_latitude(),
#                                                              $self->get_longitude(),
#                                                              $self->get_map_datum());
#         my $noaa_link = (qq(<a href="$noaa_url">NOAA weather forecast for )
#                          . $self->get_name()
#                          . "</a>");
#         $links{$noaa_link} = 1;
#     } else {
#         foreach my $area ($self->get_areas_collection()->get_all()) {
#             my $forecast_id = $area->get_weather_id();
#             next unless $forecast_id;
#             my $link = Scramble::Reference::get_reference_html_with_name_only({ 'id' => $forecast_id });
#             $links{$link} = 1;
#         }
#     }

#     my $elevation = (defined $self->get_elevation()
# 		     ?  $self->get_elevation()
# 		     : $self->get_max_elevation());
#     if (defined $elevation && $g_avvy_elev_threshold < Scramble::Misc::numerify($elevation)) {
# 	$links{Scramble::Reference::get_reference_html_with_name_only(Scramble::Reference::get_reference_for_id('avvyForecast'))} = 1;
#     }
    
#     my $sunrise_link = $self->get_sunrise_link_html();
#     if ($sunrise_link) {
#         $links{$sunrise_link} = 1;
#     }

#     return keys %links;
# }

# sub get_sunrise_link_html {
#     my $self = shift;

#     if ($self->get_latitude()) {
# 	my $lat = $self->get_latitude();
# 	my $lon = $self->get_longitude();
# 	$lat = $lat > 0 ? "N$lat" : ($lat =~ s/^-//, "S$lat");
# 	$lon = $lon > 0 ? "E$lon" : ($lon =~ s/^-//, "W$lon");
# 	return sprintf(qq(<a href="http://www.cmpsolv.com/cgi-bin/sunset?page=bob&exper=new99&loctype=Latitude&loc=%s+%s&date=&tz=Local&tzcustom=&q=&aviation=yes&day1=yes&colors=white&datefmt=0">Sunrise/Sunset times for %s</a>),,
# 		       $lat,
# 		       $lon,
# 		       $self->get_name());
#     } elsif ($self->get_state_abbreviation()) {
# 	my $id = sprintf("sunset%s", $self->get_state_abbreviation());
# 	return Scramble::Reference::get_reference_html_with_name_only({ 'id' => $id });
#     } else {
#       return undef;
#     }
# }

sub get_reports_for_location_html {
    my ($location_xml) = @_;

    my @references_html = Scramble::Reference::get_page_references_html($location_xml->get_references());

    my @reports = Scramble::Report::get_reports_for_location($location_xml);
    return undef unless @reports || @references_html;

    foreach my $report (@reports) {
	push @references_html, sprintf("$Scramble::Misc::gSiteName: %s", $report->get_link_html());
    }

    return '<ul><li>' . join('</li><li>', @references_html) . '</li></ul>';
}

sub make_locations_index {
    my $html = <<EOT;
This is an old page.  You may find what you want on the 
<a href="../../g/r/index.html">trip reports page</a>
or on the <a href="../../g/m/quad-layout.html">USGS quad layout page</a>
EOT
    Scramble::Misc::create("l/index.html", 
			   Scramble::Misc::make_2_column_page("Old Page",
							      $html));
							      
}
sub make_quads {
    my $html = <<EOT;
This is an old page.  You may find what you want on the 
<a href="../../g/r/index.html">trip reports page</a>
or on the <a href="../../g/m/quad-layout.html">USGS quad layout page</a>
EOT
    Scramble::Misc::create("m/quads-by-location.html",
			   Scramble::Misc::make_2_column_page("Old Page", 
							      $html));
}

sub dedup {
    my (@locations) = @_;

    my %locations;
    foreach my $location (@locations) {
        $locations{$location->get_id()} = $location;
    }

    return values %locations;
}

sub get_locations_referenced {
    my ($text) = @_;

    my @locations_visited;
    foreach my $regex (get_all_regex_keys()) {
	if ($text =~ s/\b$regex\b//) {
            push @locations_visited, get_regex_value($regex);
	}
    }

    return dedup(@locations_visited);
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
sub get_regex_value {
    my ($key) = @_;

    return $g_location_names_to_objects_mapping{$key};
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
sub get_all_regex_keys {
    if (! keys %g_location_names_to_objects_mapping) {
	foreach my $location (get_visited(), get_unvisited()) {

            # Need a better criteria.
            next unless $location->get_latitude();

	    foreach my $key ($location->get_regex_keys()) {
		$g_location_names_to_objects_mapping{$key} = $location;
	    }
	}
    }

    # Sort by length so "green ridge lake" in the trip report will not
    # be matched to "green ridge".
    return sort { length($b) <=> length($a) } keys %g_location_names_to_objects_mapping;
}


sub get_location_in_radians {
    my $self = shift;

    die "No location" unless defined $self->get_latitude();

    return (Math::Trig::deg2rad($self->get_longitude()), 
	    Math::Trig::deg2rad(90 - $self->get_latitude()));
}
sub get_miles_from {
    my $self = shift;
    my ($location) = @_;

    # This seems to be within a mile or two of correct.
    my $kilometers = Math::Trig::great_circle_distance($self->get_location_in_radians(), 
						       $location->get_location_in_radians(), 
						       6378);
    return $kilometers / 1.609344;
}
sub find_nearby_peaks {
    my $self = shift;
    my ($distance_threshold) = @_;

    return () unless defined $self->get_latitude();

    my @this_radians = $self->get_location_in_radians();

    my @locations;
    foreach my $location (get_visited()) {
	next unless $location->is_high_point();
	next if $location eq $self;
	next unless defined $location->get_latitude();
	my $miles = $self->get_miles_from($location);
	next unless defined $miles;
	next unless $miles <= $distance_threshold;
	push @locations, { 'location' => $location,
			   'miles' => $miles,
		       };
    }

    return @locations;
}

1;
