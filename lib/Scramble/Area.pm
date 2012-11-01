package Scramble::Area;

use strict;

use Scramble::XML ();
use Scramble::Collection ();
use Scramble::Area::Quad ();

our @ISA = qw(Scramble::XML);

my $g_all;

sub new {
    my $arg0 = shift;
    my ($xml) = @_;

    my $self = { 'xml' => $xml,
		 'locations' => {},
	     };
    bless($self, ref($arg0) || $arg0);

    if ($self->get_type() eq 'USGS quad') {
	return Scramble::Area::Quad->new($self);
    } else {
	return $self;
    }
}

sub county_matches {
    my ($location_xml, $area) = @_;

    return 0 unless $area->get_type() eq 'county';

    my $id = $location_xml->{'id'} || $location_xml->{'county'};
    $id or die "Unable to get location name";

    my $alt_id = $id;
    $alt_id =~ s/\s//g;

    return 1 if $area->get_id() eq $alt_id;
    return 1 if $area->get_id() eq "${alt_id}County";

    return 1 if $area->get_id() eq $id;
    return 1 if $area->get_id() eq "${id}County";
    return 1 if $area->get_name() eq $id;
    return 0;
}

sub get_county_high_point_html {
    my $self = shift;

    return '' unless $self->get_type() eq 'county';
    return '' unless $self->in_washington();

    my ($list) = grep { 'WACountyHighPoints' eq $_->{'id'} } Scramble::List::get_all_lists();
    if (! defined $list) {
        warn "Unable to find WACountyHighPoints";
        return '';
    }

    my ($location_xml) = grep { county_matches($_, $self) } Scramble::List::get_location_xmls($list);
    if (! $location_xml) {
        warn sprintf("Unable to find '%s' in list", $self->get_id());
        return '';
    }

    my ($quad) = Scramble::Area::get_all()->find("type" => "USGS quad",
                                                 "id" => $location_xml->{'quad'});
    my $quad_name = $location_xml->{'quad'} . " quad";
    $quad = $quad ? $quad->get_short_link_html($quad_name) : $quad_name;
    my $location = eval { Scramble::Location::find_location("name" => $location_xml->{'name'},
                                                            "quad" => $location_xml->{'quad'}) };
    $location = $location ? $location->get_short_link_html() : $location_xml->{'name'};
    my $title = qq(<a href="http://cohp.org/wa/washington.html">County high point</a>);
    return Scramble::Misc::make_colon_line($title,
                                           "$location ($quad)");
}

sub in_washington {
    my $self = shift;

    my $area;
    eval { 
        $area = $self->get_in_areas_collection()->find_one('type' => 'state',
                                                           'id' => 'WA');
    };
    return $area ? 1 : 0;
}

sub get_name { $_[0]->_get_required('name') }
sub get_short_name { $_[0]->get_name() }
sub get_id { $_[0]->_get_required('id') }
sub get_weather_id { $_[0]->_get_optional('weather-id') }
sub get_type { $_[0]->_get_required('type') }
sub get_is_recognizable_area { $_[0]->_get_optional('is-recognizable-area') ? 'true' : 0 }
sub get_info_url { $_[0]->_get_optional('URL') }

sub in_areas_transitive_closure {
    my $self = shift;

    my @areas;
    foreach my $area ($self->get_in_areas_collection()->get_all()) {
        push @areas, $area;
        push @areas, $area->in_areas_transitive_closure();
    }

    return @areas;
}

sub equals {
    my $self = shift;
    my ($obj) = @_;

    return $self->get_id() eq $obj->get_id();
}

sub get_in_areas_collection {
    my $self = shift;

    if (! $self->{'in-areas-object'}) {
	# Need to do this lazily because it needs to happen after all area objects have been opened.
	my @areas = map { Scramble::Area::get_all()->find_one('id' => $_) } $self->in_area_ids();
	$self->{'in-areas-object'} = Scramble::Collection->new('objects' => \@areas);
	$self->{'in-areas-object'}->add($self->in_areas_transitive_closure());
    }
    return $self->{'in-areas-object'};
}
sub in_area_objects { $_[0]->get_in_areas_collection()->get_all() }
sub in_area_ids {
    my $self = shift;

    my $ids = $self->_get_optional('in-areas');
    return () unless $ids;
    return split(/,\s*/, $ids);
}

sub get_relative_path {
    my $self = shift;

    return sprintf("a/%s.html",
		   Scramble::Misc::make_location_into_path($self->get_id()));

}

sub get_short_link_html {
    my $self = shift;
    my ($optional_name) = @_;

    return sprintf(qq(<a href="../../g/%s">%s</a>),
		   $self->get_relative_path(),
		   $optional_name || $self->get_short_name());
}

sub get_link { 
    my $self = shift;

    return sprintf("%s: %s",
		   ucfirst $self->get_type(),
		   $self->get_short_link_html($self->get_name()));
}

sub get_info_link {
    my $self = shift;

    if ($self->get_info_url()) {
	return sprintf(qq(<a href="%s">%s</a>),
		       $self->get_info_url(),
		       $self->get_name());
    } else {
	return $self->get_name();
    }
}

sub get_locations { values %{ $_[0]->{'locations'} } }
sub add_location {
    my $self = shift;
    my ($location) = @_;

    $self->{'locations'}{$location->get_id()} = $location;
}

my %g_area_id_to_reports;
sub get_reports {
    my $self = shift;

    if (! %g_area_id_to_reports) {
	foreach my $report (Scramble::Report::get_all()) {
	    next if $report->get_state() eq 'planned';
	    foreach my $area ($report->get_areas_collection()->get_all()) {
		push @{ $g_area_id_to_reports{$area->get_id()} }, $report;
	    }
	}
    }

    return @{ $g_area_id_to_reports{$self->get_id()} || [] };
}

sub get_reports_html {
    my $self = shift;

    my @reports = $self->get_reports();
    return '' unless @reports;

    my $html = sprintf("<h2>Trip Reports for %s</h2> <ul>", $self->get_name());
    foreach my $report (@reports) {
	$html .= sprintf("<li>%s</li>", $report->get_link_html());
    }
    return $html . "</ul>";
}

sub get_misc_html {
    my $self = shift;

    if (! $self->get_info_url()) {
	return '';
    }

    my $display_info_url = (length $self->get_info_url() > 30
			    ? substr($self->get_info_url(), 0, 30) . "..."
			    : $self->get_info_url());
    return Scramble::Misc::make_colon_line("More Info", 
					   sprintf(qq(<a href="%s">%s</a>),
						   $self->get_info_url(),
						   $display_info_url));
}
sub peak_sort {
    # so dumb
    my ($a, $b) = @_;

    return ($a eq 'peak'
	    ? -1
	    : ($b eq 'peak'
	       ? 1
	       : $a cmp $b));
}
sub get_locations_html {
    my $self = shift;

    return '' unless scalar($self->get_locations());

    my @locations = sort { $a->get_name() cmp $b->get_name() } $self->get_locations();

    my $suffix = $self->get_name() =~ /Area$/ ? "" : " Area";
    my $html = sprintf("<h2>Locations in %s%s</h2>",
		       $self->get_name(),
                       $suffix);
    if (15 > scalar(@locations)) {
	return  sprintf("$html<ul><li>%s</li></ul>",
			join("</li><li>", map { $_->get_link_html() } @locations));
    }

    my %by_type;
    foreach my $location (@locations) {
	$by_type{$location->get_type()} .= sprintf("<li>%s</li>", $location->get_link_html());
    }

    foreach my $type (sort { peak_sort($a, $b) } keys %by_type) {
	$html .= sprintf("<h3>%s</h3> <ul>%s</ul>", 
			 ucfirst(Scramble::Misc::pluralize(2, $type)),
			 $by_type{$type});
    }

    return $html;
}

sub get_images {
    my $self = shift;

    my @images = Scramble::Misc::get_images_for_locations($self->get_locations());

## If a report spans quads, this puts pictures of one quad in
## another quad's page:
#    push @images, map { $_->get_picture_objects() } $self->get_reports();

    push @images, Scramble::Image::get_all_images_collection()->find('areas' => $self);

    return @images;
}

sub cmp {
    my $self = shift;
    my ($other) = @_;

    return $self->get_id() cmp $other->get_id();
}

sub make_page {
    my $self = shift;

    my $area_type_html = '';
    if ($self->get_type() ne 'area') {
        $area_type_html = Scramble::Misc::make_colon_line("Area type", $self->get_type());
    }

    my $report_html = $self->get_reports_html();

    my $misc_html = $self->get_misc_html();

    my $county_high_point_html = $self->get_county_high_point_html();

    my $locations_html = $self->get_locations_html();

    my $in_areas_html = '';
    if ($self->in_area_objects()) {
	$in_areas_html = sprintf("<h2>Areas %s is inside of</h2> <ul><li>%s</li></ul>",
				 $self->get_name(),
				 join("</li><li>", sort map { $_->get_link() } $self->in_area_objects()));
    }

    my $text_html = <<EOT;
$area_type_html
$county_high_point_html
$misc_html

$report_html
$locations_html
$in_areas_html
EOT

    my $map_html = Scramble::Misc::get_multi_point_embedded_google_map_html([$self->get_locations()]);
    my $cells_html = Scramble::Misc::render_images_into_flow(htmls => [ $text_html, $map_html ],
							     images => [ Scramble::Image::get_best_images($self->get_images) ]);

    my $title = $self->get_name();
    my $html = <<EOT;
<h1>$title</h1>
$cells_html
EOT

    Scramble::Misc::create($self->get_relative_path(),
			   Scramble::Misc::make_1_column_page(title => $title,
							      'include-header' => 1,
							      'html' => $html,
                                                              'enable-embedded-google-map' => $Scramble::Misc::gEnableEmbeddedGoogleMap));
}

######################################################################
# statics
######################################################################

sub area_sort {
    my ($a, $b) = @_;

    if ($a->get_type() ne $b->get_type()) {
	return $a->get_type() cmp $b->get_type();
    }
    return $a->get_name() cmp $b->get_name();
}

sub get_all { $g_all }

sub make_pages {
    my @links;
    foreach my $area (sort { area_sort($a, $b) } $g_all->get_all()) {
	$area->make_page();
	push @links, $area->get_link();
    }

    
    my $html = sprintf("<ul><li>%s</li></ul>",
		       join("</li><li>", @links));
    Scramble::Misc::create("a/area-index.html",
			 Scramble::Misc::make_2_column_page("Areas",
							    $html));
}

sub open {
    return if $g_all;

    my @areas;
    my $areas_xml = Scramble::XML::parse("./data/areas.xml");
    foreach my $area_xml (@{ $areas_xml->{'area'} }) {
	my $area = Scramble::Area->new($area_xml);
	push @areas, $area;
    }

    $g_all = Scramble::Collection->new('objects' => \@areas);

    foreach my $quad ($g_all->find('type' => 'USGS quad')) {
	foreach my $dirs (['north', 'south'], ['south', 'north'], ['east', 'west'], ['west', 'east']) {
	    my $neighbor_id = $quad->get_neighboring_quad_id($dirs->[0]);
	    next unless $neighbor_id;

	    my $neighbor = eval { Scramble::Area::get_all()->find_one('id' => $neighbor_id) };
	    if (! $neighbor) {
		$neighbor = Scramble::Area::Quad->new({ 'xml' => { 'id' => $neighbor_id,
								   $dirs->[1] => $quad->get_id(),
								   'type' => $quad->get_type(),
							       }});
		get_all()->add($neighbor);
	    }
	    $neighbor->add_neighboring_quad_id($dirs->[1], $quad->get_id());
	}
    }
}

######################################################################

1;
