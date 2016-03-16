package Scramble::Report;

use strict;

use XML::RSS ();
use MIME::Types ();
use DateTime ();
use DateTime::Format::Mail ();
use JSON ();
use Scramble::Waypoints2 ();
use Scramble::Image ();
use Scramble::Reference ();

our @ISA = qw(Scramble::XML);

my $g_reports_on_index_page = 25;

my %location_to_reports_mapping;
my $g_report_collection = Scramble::Collection->new();
my $g_max_rating = 5;

sub new {
    my ($arg0, $path) = @_;

    my $self = Scramble::XML::parse($path);
    bless($self, ref($arg0) || $arg0);
    if ($self->{'skip'}) {
	return undef;
    }

    $self->{'waypoints'} = Scramble::Waypoints2->new($self->get_filename(),
						     $self->_get_optional('waypoints'));

    my @location_objects;
    foreach my $location_element ($self->get_locations()) {
	push @location_objects, Scramble::Location::find_location('name' => $location_element->{'name'},
								   'quad' => $location_element->{'quad'},
								   'country' => $location_element->{country},
								   'include-unvisited' => 1,
								   );
    }
    $self->{'location-objects'} = \@location_objects;
    foreach my $location ($self->get_location_objects()) {
	$location->set_have_visited();
    }

    {
	my @areas;
	push @areas, map { $_->get_areas_collection->get_all() } $self->get_location_objects();
	push @areas, $self->get_areas_from_xml();
	@areas = Scramble::Misc::dedup(@areas);
	$self->{'areas-object'} = Scramble::Collection->new('objects' => \@areas);
    }

    $self->set('start-date', Scramble::Time::normalize_date_string($self->get_start_date()));
    if (defined $self->get_end_date()) {
	$self->set('end-date', Scramble::Time::normalize_date_string($self->get_end_date()));
    }

    my @images = Scramble::Image::read_images_from_report(File::Basename::dirname($path), $self);
    my $image_collection = Scramble::Collection->new(objects => \@images);

    my $picture_objs = [ $image_collection->find('type' => 'picture') ];

    if (@$picture_objs && $picture_objs->[0]->in_chronological_order()) {
        $picture_objs = [ sort { $a->get_chronological_order() <=> $b->get_chronological_order() } @$picture_objs ];
    }
    $self->set_picture_objects([ grep { ! $_->get_should_skip_report() } @$picture_objs]);

    $self->{'map-objects'} = [ $image_collection->find('type' => 'map') ];

    my @kmls = $image_collection->find('type' => 'kml');
    die "Too many KMLs" if @kmls > 1;
    $self->{'kml'} = $kmls[0] if @kmls;

    if ($self->should_show()) {
        foreach my $image (@$picture_objs, $self->get_map_objects()) {
            $image->set_report_url($self->get_report_page_url());
            $image->set_pager_url(sprintf("%s?%s#", $self->get_pager_url(), $image->get_id()));
        }
    }

    return $self;
}

sub get_id { $_[0]->get_start_date() . "|" . ($_[0]->get_trip_id() || "") }
sub get_trip_id { $_[0]->_get_optional('trip-id') }
sub get_trip_organizer { $_[0]->_get_optional('trip-organizer') || 'private' }
sub get_areas_collection { $_[0]->{'areas-object'} }
sub get_waypoints { $_[0]->{'waypoints'} }
sub get_type { $_[0]->_get_optional('type') || 'scramble' }
sub get_end_date { $_[0]->_get_optional('end-date') }
sub get_start_date { $_[0]->_get_required('start-date') }
sub get_name { $_[0]->_get_required('name') }
sub get_locations { @{ $_[0]->_get_optional('locations', 'location') || [] } }
sub get_location_objects { @{ $_[0]->{'location-objects'} } }
sub get_state { $_[0]->_get_optional('state') || "done" }
sub is_planned { $_[0]->get_state() eq 'planned' }
sub get_route { $_[0]->_get_optional_content('description') }
sub get_rock_routes { @{ $_[0]->_get_optional('rock-routes', 'rock-route') || [] } }
sub get_kml { $_[0]->{kml} }
sub get_map_objects { @{ $_[0]->{'map-objects'} } }
sub get_picture_objects { @{ $_[0]->{'picture-objects'} } }
sub set_picture_objects { $_[0]->{'picture-objects'} = $_[1] }


sub get_filename {
    my $self = shift;
    return $self->_get_required('filename') . ".html";
}
sub get_pager_filename {
    my $self = shift;
    return $self->_get_required('filename') . "_pager.html";
}

sub get_best_picture_object {
    my $self = shift;

    my $best_image;
    foreach my $image ($self->get_picture_objects()) {
        $best_image = $image if ! defined $best_image;
        $best_image = $image if $best_image->get_rating() >= $image->get_rating();
    }
    return $best_image;
}

sub get_leaders {
    my $self = shift;

    my $party_xml = $self->_get_optional_content('party');
    return () unless $party_xml;

    my @leaders;
    foreach my $member (@{ $party_xml->{'member'} }) {
        next unless defined $member->{'type'};
        if ($member->{'type'} =~ /leader/i && $member->{'type'} !~ /assistant/) {
            push @leaders, $member->{'name'};
        }
    }

    return @leaders;
}

sub get_num_days {
  my $self = shift;

  if (! defined $self->get_end_date()) {
    return 1;
  }

  my ($syear, $smonth, $sday) = Scramble::Time::parse_date($self->get_start_date());
  my ($eyear, $emonth, $eday) = Scramble::Time::parse_date($self->get_end_date());

  if (! defined $syear) {
    return 1;
  }

  my $start = Date::Manip::Date_DaysSince1BC($smonth, $sday, $syear);
  my $end = Date::Manip::Date_DaysSince1BC($emonth, $eday, $eyear);

  return 1 + $end - $start;
}

sub should_show {
    my $self = shift;
    if ($self->_get_optional('should-not-show')) {
	return 0;
    }
    return 1;
}

sub link_if_should_show {
    my $self = shift;
    my ($html) = @_;

    return ($self->should_show() 
            ? sprintf(qq(<a href="%s">%s</a>), $self->get_report_page_url(), $html) 
            : $html);
}

sub get_parsed_start_date {
    my $self = shift;

    my @date = split('/', $self->get_start_date());
    @date == 3 or die sprintf("Bad start date '%s'", $self->get_start_date());
    return @date;
}

sub get_maps { 
    my $self = shift;

    my @maps;
    push @maps, map { $_->get_map_reference() } $self->get_map_objects();
    push @maps, @{ $self->_get_optional('maps', 'map') || [] };

    return grep { ! $_->{'skip-map'} } @maps;
}

sub get_report_page_url {
    my $self = shift;

    return sprintf("../../g/r/%s", $self->get_filename());
}

sub get_pager_url {
    my $self = shift;

    return sprintf("../../g/r/%s", $self->get_pager_filename());
}

sub get_link_html {
    my $self = shift;

    my $date = $self->get_start_date();
    if (defined $self->get_end_date()) {
	$date .= " to " . $self->get_end_date();
    }

    my $name = $self->link_if_should_show($self->get_name());
    if ($self->get_state() ne 'done') {
	$name .= sprintf(" (%s)", $self->get_state());
    }

    my $image_html = '';
    if ($self->should_show()) {
	my $image_obj = $self->get_best_picture_object();
	if ($image_obj) {
	    my $size = 125;
	    $image_html = sprintf(qq(<img width="$size" onload="resizeThumbnail(this, $size)" src="%s">),
				  $image_obj->get_url());
            $image_html = $self->link_if_should_show($image_html);
	}
    }

    my $type = $self->get_type();

    my $html = <<EOT;
<div class="report-thumbnail">
    <div class="report-thumbnail-image">$image_html</div>
    <div class="report-thumbnail-title">$name</div>
    <div class="report-thumbnail-date">$date</div>
    <div class="report-thumbnail-type">$type</div>
</div>
EOT

    return $html;
}

sub get_embedded_google_map_html {
    my $self = shift;

    return '' if $self->get_map_objects();

    my @locations = $self->get_location_objects();
    my $kml_url = $self->get_kml() ? $self->get_kml()->get_full_url() : undef;
    return '' unless $kml_url or grep { defined $_->get_latitude() } @locations;

    my %options = ('kml-url' => $kml_url);
    return Scramble::Misc::get_multi_point_embedded_google_map_html(\@locations, \%options);
}

sub get_distances_html {
    my $self = shift;

    my $distances = $self->_get_optional('round-trip-distances', 'distance');
    if (! $distances) {
	# <times miles=""> is deprecated 
	my $miles = $self->_get_optional('times', 'miles');
	if (! $miles) {
	    return '';
	}
	return sprintf("<b>Round-trip distance:</b> approx. %s %s<br>",
		       $miles,
		       Scramble::Misc::pluralize($miles, "mile"));
    }

    my @parenthesis_htmls;
    my $total_miles = 0;
    foreach my $distance (@$distances) {
	$total_miles += $distance->{'miles'};
	push @parenthesis_htmls, sprintf("%s %s on %s",
					 $distance->{'miles'},
					 Scramble::Misc::pluralize($distance->{'miles'}, "mile"),
					 $distance->{'type'});
    }

    return sprintf("<b>Round-trip distance:</b> approx. %s %s%s<br>",
		   $total_miles,
		   Scramble::Misc::pluralize($total_miles, 'mile'),
		   (@parenthesis_htmls == 1 ? '' : " (" . join(", ", @parenthesis_htmls) . ")"));
}

sub get_references {
    my $self = shift;

    my @references = @{ $self->_get_optional('references', 'reference') || [] };
    @references = sort { Scramble::Reference::cmp_references($a, $b) } @references;

    return @references;
}

sub get_reference_html {
    my $self = shift;

    my @references = map { Scramble::Reference::get_page_reference_html($_) } $self->get_references();
    @references = Scramble::Misc::dedup(@references);

    return '' unless @references;

    return '<ul><li>' . join('</li><li>', @references) . '</li></ul>';
}

sub get_map_summary_html {
    my $self = shift;

    return '' if defined $self->_get_optional('maps') && ! defined $self->_get_optional('maps', 'map');

    my $type = 'USGS quad';
    my %maps;

    foreach my $map ($self->get_maps()) {
        my $map_type = Scramble::Reference::get_map_type($map);
        next unless defined $map_type && $type eq $map_type;
        my $name = Scramble::Reference::get_map_name($map);
        $maps{$name} = 1;
    }

    if ($type eq 'USGS quad') {
        foreach my $location ($self->get_location_objects()) {
            foreach my $quad ($location->get_quad_objects()) {
                $maps{$quad->get_short_name()} = 1;
            }
        }

        foreach my $area ($self->get_areas_collection()->find('type' => 'USGS quad')) {
            $maps{$area->get_short_name()} = 1;
        }
    }

    my @maps = keys %maps;
    return '' unless @maps;
    return '' if @maps > 15;

    my $title = Scramble::Misc::pluralize(scalar(@maps), $type);
    return Scramble::Misc::make_colon_line($title, join(", ", @maps));
}

sub make_pager_html {
    my $self = shift;

    my @images;
    foreach my $image ($self->get_map_objects(), $self->get_picture_objects()) {
	my $url = $image->get_enlarged_img_url() || $image->get_url();
        push @images, { 
			description => $image->get_description(),
			"report-link" => $self->link_if_should_show($self->get_start_date()),
			id => $image->get_id(),
			src => $url,
	              };
    }
    my $images_js = JSON::encode_json(\@images);

    my $html = <<EOT;
<style>
body {
    width: 98%;
    height: 100%;
    margin-left: auto;
    margin-right: auto;
}

.left-pager-image, .right-pager-image {
    height: 500px;
    border: none;
}
.left-pager-image {
    margin-right: auto;
    margin-left: 0;
}
.right-pager-image {
    margin-left: auto;
    margin-right: 0;
}

.left-pager, .right-pager {
    position: relative;
    z-index: 2;
    display: block;
    float: left;
    width: 10%;
    vertical-align: top;
}
.left-pager {
    text-align: left;
}
.right-pager {
    text-align: right;
}

.image-container {
    position: relative;
    z-index: -1;
    display: block;
    float: left;
    width: 80%;
    height: 100%;
    min-height: 100px;
}
.image {
    margin-left: auto;
    margin-right: auto;
    display:block;
}
</style>
<script type="text/javascript">
    var currentImageIndex = 0;
    var images = $images_js;

function loadPage() {
    var img = document.getElementById('page-image');
    var imgContainer = img.parentNode;
    imgContainer.removeChild(img);

    var newImg = document.createElement('img');
    newImg.className = 'image';
    newImg.id = 'page-image';
    newImg.src = images[currentImageIndex]['src'];
    imgContainer.appendChild(newImg);

    document.getElementById('description').innerHTML = images[currentImageIndex]['description'];
    document.getElementById('report-link').innerHTML = images[currentImageIndex]['report-link'];
    document.getElementById("left-pager-link").style.visibility = (currentImageIndex === 0 ? 'hidden' : 'visible');
    document.getElementById("right-pager-link").style.visibility = (currentImageIndex === images.length - 1 ? 'hidden' : 'visible');
}
function firstPage() {
    var matches = /\\?(.+)#\$/.exec(window.location);
    currentImageIndex = null;
    if (matches !== null) {
        var imageId = matches[1];
        for (var i = 0; i < images.length; ++i) {
            if (imageId === images[i].id) {
                currentImageIndex = i;
            }
        }
    }
    if (currentImageIndex === null || currentImageIndex < 0 || currentImageIndex >= images.length) {
        currentImageIndex = 0;
    }
    loadPage();
}
function nextPage() {
    currentImageIndex++;
    loadPage();
}
function previousPage() {
    currentImageIndex--;
    loadPage();
}
currentImageIndex</script>
<br />
<div class="left-pager">
	<a id="left-pager-link" href="#" onclick="previousPage()"><img class="left-pager-image" src="../../pics/pager-previous.png" /></a>
</div>
<div class="image-container">
	<img class="image" id="page-image"/>
</div>
<div class="right-pager">
	<a id="right-pager-link" href="#" onclick="nextPage()"><img class="right-pager-image" src="../../pics/pager-next.png" /></a>
	<div class="image-description" id="description"></div>
        <br />
	<div class="report-link" id="report-link"></div>
</div>

<script type="text/javascript">
	firstPage();
</script>
EOT

    my $title = sprintf("%s (pictures)", $self->get_title_html());
    Scramble::Misc::create(sprintf("r/%s", $self->get_pager_filename()),
			   Scramble::Misc::make_1_column_page('include-header' => 1,
							      'skip-footer' => 1,
							      'title' => $title,
							      'html' => $html));
}

sub make_page_html {
    my $self = shift;
    my @args = @_;

    eval {
	$self->make_spare_page_html(@args);
	$self->make_pager_html(@args);
    };
    if ($@) {
	local $SIG{__DIE__};
	die sprintf("Error while making HTML for %s:\n%s",
		    $self->{'path'},
		    $@);
    }
}

sub make_date_html {
    my $self = shift;

    my $date = $self->get_start_date();
    if (defined $self->get_end_date()) {
	$date .= " to " . $self->get_end_date();
    }

    return Scramble::Misc::make_colon_line("Date", $date);
}

sub get_copyright_html {
    my $self = shift;

    my $copyright_year = $self->get_end_date() ? $self->get_end_date() : $self->get_start_date();
    ($copyright_year) = Scramble::Time::parse_date($copyright_year);

    return $copyright_year;
}

sub get_title_html {
    my $self = shift;

    return $self->get_name();
}

sub get_elevation_gain_html {
    my $self = shift;

    return Scramble::Misc::make_optional_line("<b>Elevation gain:</b> approx. %s<br>",
                                              $self->get_waypoints()->get_elevation_gain("ascending|descending"));
}

sub split_by_date {
    my @picture_objs = @_;

    return ([]) if !@picture_objs;

    my $curr_date = $picture_objs[0]->get_capture_date();
    return (\@picture_objs) unless defined $curr_date;

    my @splits;
    my $split = [];
    foreach my $picture_obj (@picture_objs) {
        if ($curr_date eq $picture_obj->get_capture_date()) {
            push @$split, $picture_obj;
        } else {
            push @splits, $split;
            $split = [ $picture_obj ];
            $curr_date = $picture_obj->get_capture_date();
        }
    }
    push @splits, $split;

    return @splits;
}

sub make_spare_page_html {
    my $self = shift;

    my $date = $self->make_date_html();
    my $trip_type = Scramble::Misc::make_colon_line("Trip type", $self->get_type());
    my $elevation_html = $self->get_elevation_gain_html();
    my $miles_html = $self->get_distances_html();
    my $quads_html = $self->get_map_summary_html();
    my $recognizable_areas_html = $self->get_recognizable_areas_html('no-link' => 1);
    my $short_route_references = '';
    my $long_route_references = '';
    if ($self->get_references() == 1) {
      $short_route_references = Scramble::Misc::make_colon_line("Reference", 
								Scramble::Reference::get_reference_html_with_name_only($self->get_references(),
														      'name-ids' => [qw(page-name name)]));
    } else {
      $long_route_references = Scramble::Misc::make_optional_line("<h2>References</h2>%s",
							     $self->get_reference_html());
    }

    my $long_times_html = '';
    my $short_times_html = '';
    if ($self->get_waypoints()->get_waypoints_with_times() > 2) {
      $long_times_html = $self->get_waypoints()->get_detailed_time_html();
    } else {
        # Some reports have zero waypoints but still have a car-to-car time.
        $short_times_html = $self->get_waypoints()->get_car_to_car_html();
    }

    my $right_html = <<EOT;
$date
$trip_type
$elevation_html
$miles_html
$short_times_html
$quads_html
$recognizable_areas_html
$short_route_references
$long_times_html
$long_route_references
EOT

    my @htmls;
    push @htmls, $right_html;

    my $map_html = $self->get_embedded_google_map_html();
    push @htmls, $map_html if $map_html;

    my $cells_html;
    my @map_objects = $self->get_map_objects();
    my $start_days = Scramble::Time::get_days_since_1BC($self->get_start_date());
    my $count = 1;
    my @picture_objs = split_by_date($self->get_picture_objects());
    foreach my $picture_objs (@picture_objs) {
	my $day = $count;
	# Handle trips where I don't take a picture every day:
	if (@$picture_objs && defined $picture_objs->[0]->get_capture_date()) {
	    my $picture_days = Scramble::Time::get_days_since_1BC($picture_objs->[0]->get_capture_date());
	    $day = $picture_days - $start_days + 1;
	}
	if (@picture_objs > 1) {
	    if ($count == 1) {
		$cells_html .= Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
								       'images' => [@map_objects ],
								       'pager-links' => 1,
								       'no-float-first' => 0,
								       'no-report-link' => 1);
		@htmls = @map_objects = ();
	    }
	    $cells_html .= "<h1>Day $day</h1>";
	}

        $cells_html .= Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
 							       'images' => [@map_objects, @$picture_objs ],
							       'pager-links' => 1,
                                                               'no-float-first' => 0,
							       'no-report-link' => 1);
        @htmls = @map_objects = ();
        $count++;
    }	

    my $route = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("%s", $self->get_route()));
    if ($route) {
	$route = "<p>$route</p>";
    }

    my $title = $self->get_title_html();
    if ($self->get_state() eq 'attempted') {
      $title .= sprintf(" (%s)", $self->get_state());
    }

    my $html = <<EOT;
<h1>$title</h1>
$route
$cells_html
EOT

    my $copyright_year = $self->get_copyright_html();
    Scramble::Misc::create(sprintf("r/%s", $self->get_filename()),
			   Scramble::Misc::make_1_column_page('title' => $title, 
							      'include-header' => 1,
							      'html' => $html,
                                                              'enable-embedded-google-map' => $Scramble::Misc::gEnableEmbeddedGoogleMap,
							      'copyright-year' => $copyright_year));
}

######################################################################
# statics
######################################################################

sub make_all_report_pages {
    foreach my $report_xml (get_all()) {
	$report_xml->make_page_html();
    }
}

sub equals {
    my $self = shift;
    my ($report) = @_;

    return $report->get_id() eq $self->get_id();
}

sub cmp {
    my ($report1, $report2) = @_;

    if ($report1->get_start_date() ne $report2->get_start_date()) {
        return $report1->get_start_date() cmp $report2->get_start_date();
    }

    if (! defined $report1->get_trip_id() || ! defined $report2->get_trip_id()) {
        return defined $report1->get_trip_id() ? 1 : -1;
    }

    return $report1->get_trip_id() cmp $report2->get_trip_id();
}

sub open_specific {
    my ($path) = @_;

    my $report = Scramble::Report->new($path);
    $g_report_collection->add($report) if defined $report;
    return $report;
}

sub open_all {
    my ($directory) = @_;

    die "No such directory '$directory'" unless -d $directory;

    foreach my $path (reverse(sort(glob("$directory/*/report.xml")))) {
	open_specific($path);
    }
}

sub get_all {
    return $g_report_collection->get_all();
}

sub make_rss {
    # http://feedvalidator.org/
    # http://www.w3schools.com/rss/default.asp

    my $rss = XML::RSS->new(version => '1.0');
    my $now = DateTime::Format::Mail->format_datetime(DateTime->now());
    $rss->channel(title => 'yellowleaf.org',
		  link => 'http://yellowleaf.org/scramble/g/m/home.html',
		  language => 'en',
		  description => 'Mountains and pictures. Pictures and mountains.',
		  copyright => 'Copyright 2013, Gabriel Deal',
		  pubDate => $now,
		  lastBuildDate => $now,
	      );
    $rss->image(title => 'yellowleaf.org',
		url => 'http://yellowleaf.org/scramble/pics/favicon.jpg',
		link => 'http://yellowleaf.org/scramble/g/m/home.html',
		width => 16,
		height => 16,
		description => "It's a snowy mountain and the sun!"
	    );

    my $count = 0;
    my $mime = MIME::Types->new(only_complete => 1);
    foreach my $report (get_all()) {
        last unless ++$count <= 15; 
        next unless $report->should_show();
        my $best_image = $report->get_best_picture_object();
	next unless $best_image;

	die Data::Dumper::Dumper($best_image) . "\n\n\n\n" . Data::Dumper::Dumper($report) unless $best_image->get_enlarged_img_url();

	my $image_url = sprintf(qq(http://yellowleaf.org/scramble/%s),
				$best_image->get_enlarged_img_url());
	# The "../.." in the URL was stopping Feedly from displaying
	# an image in the feed preview.
	$image_url =~ s{\.\./\.\./}{};

        my $report_url = sprintf("http://yellowleaf.org/scramble/%s",
				 $report->get_report_page_url());
	$report_url =~ s{\.\./\.\./}{};

	my $image_html = sprintf(qq(<a href="%s"><img src="%s" alt="%s"></a>),
				 $report_url,
				 $image_url,
				 $best_image->get_description());
	my $description = qq(<![CDATA[$image_html]]>);

	$rss->add_item(title => $report->get_name(),
		       link => $report_url,
		       description => $description,
		       content => {
			   encoded => $description,
		       },
		       enclosure => { url => $image_url,
				      type => $mime->mimeTypeOf($best_image->get_filename()),
				  });
    }

    Scramble::Misc::create("r/rss.xml", $rss->as_string());
}

sub make_reports_index_page {
    my %report_htmls;
    my $count = 0;
    my $latest_year = 0;
    foreach my $report (get_all()) {
	my ($yyyy) = $report->get_parsed_start_date();
        $latest_year = $yyyy if $yyyy > $latest_year;

	my $html = $report->get_link_html();
	if ($report->get_state() eq 'planned') {
	    $report_htmls{'planned'} .= $html;
	} else {
	    $report_htmls{'all'} .= $html;
	    $report_htmls{$yyyy} .= $html;
	    if ($count++ < $g_reports_on_index_page) {
		$report_htmls{'index'} .= $html;
	    }
	}
    }
    foreach my $id (keys %report_htmls) {
	$report_htmls{$id} = sprintf(qq(<div class="report-thumbnails">%s</div>), $report_htmls{$id});
    }

    my @link_htmls;
    foreach my $id (keys %report_htmls) {
	my $title;
	if ($id eq 'planned') {
	    $title = "Planned Trips";
	} elsif ($id eq 'index') {
	    $title = "Most Recent Trips";
	} elsif ($id eq 'all') {
	    $title = "All Trips";
	} else {
	    push @link_htmls, qq(<a href="../../g/r/$id.html">$id</a>);
	    $title = "$id Trips";
	}
	$report_htmls{$id} = { 'title' => $title,
			       'html' => $report_htmls{$id},
			       'subdirectory' => "r",
			   };
    }
    @link_htmls = sort @link_htmls;
    my $report_links = sprintf("%s<br>",
			       join(", ", @link_htmls));

    # The home page slowly became almost exactly the same as the
    # reports index page.
    $report_htmls{home} = { %{ $report_htmls{index} } };
    $report_htmls{home}{subdirectory} = "m";

    foreach my $id (keys %report_htmls) {
        my $copyright_year = $id;
        if ($id !~ /^\d+$/) {
            $copyright_year = $latest_year;
        }
	Scramble::Misc::create
	    ("$report_htmls{$id}{subdirectory}/$id.html", 
	     Scramble::Misc::make_2_column_page($report_htmls{$id}{'title'},
						$report_links . $report_htmls{$id}{'html'} . $report_links,
						undef,
						'js-includes' => [ "report.js" ],
                                                'no-add-picture' => 1,
                                                'copyright-year' => $copyright_year,
						'image-size' => '50%'));
    }
}

sub get_reports_for_location {
    my ($location) = @_;

    my @retval;
    foreach my $report (get_all()) {
	next if $report->is_planned();
	push @retval, $report if grep { $location->equals($_) } $report->get_location_objects();
    }
    return @retval;
}

######################################################################
# end statics
######################################################################

1;
