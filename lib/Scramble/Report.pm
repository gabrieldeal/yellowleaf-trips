package Scramble::Report;

use strict;

use Scramble::ObjectAdaptor ();
use Scramble::Waypoints ();
use Scramble::Waypoints2 ();
use Scramble::Image ();
use Scramble::Reference ();

our @ISA = qw(Scramble::XML);

my $g_reports_on_index_page = 50;

my %location_to_reports_mapping;
my $g_report_collection;
my $g_max_rating = 5;

sub new {
    my ($arg0, $path) = @_;

    my $self = bless({}, ref($arg0) || $arg0);
    $self->{'xml'} = Scramble::XML::parse($path);
    if ($self->{'xml'}{'skip'}) {
	return undef;
    }

    if ($self->_get_optional('times')) {
	$self->{'waypoints'} = Scramble::Waypoints->new($self->get_filename(),
							$self->_get_optional('times'));
    } else {
	$self->{'waypoints'} = Scramble::Waypoints2->new($self->get_filename(),
							 $self->_get_optional('waypoints'));
    }

    my @locations_attempted;
    foreach my $location_element (@{ $self->_get_optional('locations', 'attempted') || [] }) {
        eval {
            push @locations_attempted, Scramble::Location::find_location('name' => $location_element->{'name'},
                                                                          'quad' => $location_element->{'quad'},
                                                                          'include-unvisited' => 1,
                                                                          );
        };
    }
    $self->{'locations-attempted'} = \@locations_attempted;
    my @locations_visited;
    foreach my $location_element ($self->get_locations()) {
	push @locations_visited, Scramble::Location::find_location('name' => $location_element->{'name'},
								   'quad' => $location_element->{'quad'},
								   'include-unvisited' => 1,
								   );
    }
    my @locations_not_visited;
    foreach my $location_element (@{ $self->_get_optional('locations', 'not') || [] }) {
        eval {
            push @locations_not_visited, Scramble::Location::find_location('name' => $location_element->{'name'},
                                                                           'quad' => $location_element->{'quad'},
                                                                           'include-unvisited' => 1,
                                                                           );
        };
    }
    push @locations_visited, $self->get_waypoints()->get_locations_visited();
    foreach my $location (@locations_not_visited) {
        my @tmp = grep { ! $location->equals($_) } @locations_visited;
        @locations_visited = @tmp;
    }
    $self->{'locations-visited'} = [ Scramble::Misc::dedup(@locations_visited) ];
    foreach my $location ($self->get_locations_visited()) {
	$location->set_have_visited();
    }

    {
	my @areas;
	# filter out locations that span a lot of areas:
	my @locations = grep { (! $_->get_is_driving_location() 
				&& $_->get_type() ne 'road' 
				&& $_->get_type() ne 'trail') } $self->get_locations_visited();
	push @areas, map { $_->get_areas_collection->get_all() } @locations;
	push @areas, $self->get_areas_from_xml();
	@areas = Scramble::Misc::dedup(@areas);
	$self->{'areas-object'} = Scramble::Collection->new('objects' => \@areas);
    }

    $self->set('start-date', Scramble::Time::normalize_date_string($self->get_start_date()));
    if (defined $self->get_end_date()) {
	$self->set('end-date', Scramble::Time::normalize_date_string($self->get_end_date()));
    }

    my %args = (
                'trip-id' => $self->get_trip_id(),
                'date' => $self->get_start_date(),
               );
    my $picture_objs = [ Scramble::Image::get_all_images_collection()->find(%args, 'type' => 'picture') ];
    if (@$picture_objs && $picture_objs->[0]->in_chronological_order()) {
        $picture_objs = [ sort { $a->get_chronological_order() <=> $b->get_chronological_order() } @$picture_objs ];
    }
    $self->set_picture_objects([ grep { ! $_->get_should_skip_report() } @$picture_objs]);

    $self->{'map-objects'} = [ Scramble::Image::get_all_images_collection()->find(%args, 'type' => 'map') ];

    if ($self->should_show()) {
        foreach my $image (@$picture_objs, $self->get_map_objects()) {
            $image->set_report_url($self->get_report_page_url());
        }
    }

    return $self;
}

sub get_trip_id { $_[0]->_get_optional('trip-id') }
sub get_display_mode { $_[0]->_get_optional('display-mode') || 'normal' }
sub get_trip_organizer { $_[0]->_get_optional('trip-organizer') || 'private' }
sub get_areas_collection { $_[0]->{'areas-object'} }
sub get_waypoints { $_[0]->{'waypoints'} }
sub get_locations_visited { @{ $_[0]->{'locations-visited'} } }
sub get_locations_attempted { @{ $_[0]->{'locations-attempted'} } }
sub get_type { $_[0]->_get_optional('type') || 'scramble' }
sub get_end_date { $_[0]->_get_optional('end-date') }
sub get_start_date { $_[0]->_get_required('start-date') }
sub get_name { $_[0]->_get_required('name') }
sub get_filename { $_[0]->_get_required('filename') }
sub get_special_gear { $_[0]->_get_optional('special-gear') }
sub get_locations { @{ $_[0]->_get_optional('locations', 'location') || [] } }
sub get_state { $_[0]->_get_optional('state') || "done" }
sub get_pictures { @{ $_[0]->_get_optional('pictures', 'picture') || [] } }
sub is_planned { $_[0]->get_state() eq 'planned' }
sub get_route { $_[0]->_get_optional_content('route') }
sub get_comments { $_[0]->_get_optional_content('comments') }
sub get_rock_routes { @{ $_[0]->_get_optional('rock-routes', 'rock-route') || [] } }

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

# I get problems with $a or $b being undefined if I do this the normal
# way.
sub stupid_hack($$) {
    return $_[0]->cmp($_[1]);
}
sub get_average_pic_rating {
    my $self = shift;

    my $min_images = 5;

    my @images = $self->get_picture_objects();
    if (@images < $min_images) {
        return 100; # worst rating
    }

    my @sorted_images = sort stupid_hack @images;

    my $sum = 0;
    foreach my $image (@sorted_images[0 .. $min_images-1]) {
        $sum += $image->get_rating();
    }
    return $sum / $min_images;
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
    if ($self->get_display_mode() eq 'no-links-to') {
	return 0;
    }
    return 1;
}

sub get_parsed_start_date {
    my $self = shift;

    my @date = split('/', $self->get_start_date());
    @date == 3 or die sprintf("Bad start date '%s'", $self->get_start_date());
    return @date;
}

sub get_visited_html {
    my $self = shift;

    my @objects;
    foreach my $location ($self->get_locations_visited()) {
	next if $location->get_is_driving_location();
	push @objects, $location->get_areas_collection()->get_all();
	push @objects, $location;
    }

    @objects = grep { $_->get_name() ne 'USA' } @objects;

    return Scramble::Misc::make_optional_line("<h2>Visited</h2> <ul><li>%s</li></ul>", 
					      join("</li><li>", 
						   Scramble::Misc::get_abbreviated_name_links(@objects)));
}

sub get_best_map_type {
    my $self = shift;

    my $maps_xml = $self->_get_optional('maps');
    return 'USGS quad' unless $maps_xml && $maps_xml->{'best-map-type'};
    return $maps_xml->{'best-map-type'};
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

sub get_link_html {
    my $self = shift;

    my @info;
    push @info, $self->get_state() unless $self->get_state() eq 'done';
    my $info = @info ? " (" . join(", ", @info) . ")" : '';
#     my $stars = '';
#     if (defined(my $rating = $self->get_aesthetic_rating())) {
# 	my $nstars = int($rating);
# 	my $nhalf_stars = ($rating - $nstars > 0 ? 1 : 0);
# 	my $nspaces = $g_max_rating - $nstars - $nhalf_stars;
# 	$stars = (" <nobr>"
# 		  . sprintf(qq(<img alt="(%s %s)" src="../../pics/vbar.gif">),
# 			    $rating,
# 			    Scramble::Misc::pluralize($rating, "star"))
# 		  . qq(<img alt="" src="../../pics/star.gif">) x $nstars
# 		  . qq(<img alt="" src="../../pics/half-star.gif">) x $nhalf_stars
# 		  . qq(<img alt="" src="../../pics/hbars.gif">) x $nspaces
# 		  . qq{<img alt="" src="../../pics/vbar.gif">}
# 		  . "</nobr>");
#     }

    my $pictures = '';
    if ($self->has_pictures() && $self->should_show()) {
 	$pictures = " " . Scramble::Misc::get_pictures_img_html($self->get_picture_objects());
    }

    my $link;
    if ($self->should_show()) {
	$link = sprintf(qq(<a href="%s">%s</a>),
			$self->get_report_page_url(),
			Scramble::Misc::remove_quad_specifier($self->get_name()));
    } else {
	$link = $self->get_name();
    }

    return "$link$info$pictures";
}

sub get_map_html {
    my ($self) = @_;

    my @map_references = $self->get_maps();
    #push @map_references, grep { ! $_->{'is-driving-location'} } map { $_->get_maps() } $self->get_locations_visited();
    @map_references =  sort { Scramble::Reference::cmp_references($a, $b) } @map_references;
    return '' unless @map_references;

    my @map_htmls = Scramble::Reference::get_map_htmls(\@map_references);

    my $maps_html =  Scramble::Misc::make_optional_line("<h2>Maps</h2> <ul><li>%s</li></ul>",
							@map_htmls ? join("</li><li>", @map_htmls) : undef);
}

sub get_route_map_html {
    my $self = shift;

    return Scramble::Misc::make_optional_line("<h2>Route Map</h2> %s",
					      $self->get_image_htmls('type' => 'map',
								     'no-report-link' => 1));
}

# sub get_weather_html {
#     my $self = shift;

#     my @links;
#     foreach my $location ($self->get_locations_visited()) {
# 	next if $location->get_is_driving_location();
# 	push @links, $location->get_weather_forecast_link_htmls();
#     }
#     @links = Scramble::Misc::dedup(@links);
#     @links = sort @links;

#     return Scramble::Misc::make_optional_line("<h2>Weather</h2> <ul><li>%s</li></ul>",
# 					      join("</li><li>", @links));
# }

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


sub have_empty_references {
    my $self = shift;

    if (! defined $self->_get_optional('references')) {
      return 0; # No <references> tag.
    }
    if (! defined $self->_get_optional('references', 'reference')) {
      return 1; # Have <references> but no <reference>.
    }
    return 0; # Have <references> and <reference>.
}

sub get_references {
    my $self = shift;

    my @references;

    if ($self->have_empty_references()) {
      # Means I explicitly did not want any references on this report.
      return @references;
    }

    @references = @{ $self->_get_optional('references', 'reference') || [] };
    if (! @references) {
        @references = map { $_->get_references() } $self->get_locations_visited();
    }

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

    my $type = $self->get_best_map_type();
    my %maps;

    foreach my $map ($self->get_maps()) {
        my $map_type = Scramble::Reference::get_map_type($map);
        next unless defined $map_type && $type eq $map_type;
        my $name = Scramble::Reference::get_map_name($map);
        $maps{$name} = 1;
    }

    if ($type eq 'USGS quad') {
        foreach my $location ($self->get_locations_visited()) {
            next if $location->get_is_driving_location() || $location->get_is_road();
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

    my $title = Scramble::Misc::pluralize(scalar(@maps), $type);
    return Scramble::Misc::make_colon_line($title, join(", ", @maps));
}

sub _make_page_html {
    my $self = shift;

    if ($self->get_display_mode() eq 'normal'
	|| $self->get_display_mode() eq 'no-links-to'
	|| $self->get_display_mode() eq 'spare')
    {
        return $self->make_spare_page_html();
    } else {
        die "Bad display mode: " . $self->get_display_mode();
    }
}
sub make_page_html {
    my $self = shift;
    my @args = @_;

    eval {
	$self->_make_page_html(@args);
    };
    if ($@) {
	local $SIG{__DIE__};
	die sprintf("Error while parsing %s:\n%s",
		    $self->get_filename(),
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

sub make_spare_page_html {
    my $self = shift;

    Scramble::Logger::verbose(sprintf("Rendering spare HTML for '%s'\n", 
				      $self->get_name()));

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
#        $long_times_html = Scramble::Misc::make_optional_line("<h2>Travel Times</h2> %s",
#                                                         $self->get_waypoints()->get_detailed_time_html());
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

    my $cells_html = Scramble::Misc::render_images_into_flow('htmls' => [ $right_html ],
							     'images' => [$self->get_map_objects(), $self->get_picture_objects() ]);

    my $route = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("%s", $self->get_route()));

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

sub open_all {
    my ($directory) = @_;

    die "No such directory '$directory'" unless -d $directory;

    my @reports;
    foreach my $path (reverse(glob("$directory/*.xml"))) {
	my $report = Scramble::Report->new($path);
	push @reports, $report if $report;
    }

    @reports = sort { $b->cmp($a) } @reports;
    $g_report_collection = Scramble::Collection->new('objects' => \@reports);
}


sub get_all { 
    return $g_report_collection->get_all();
}

sub make_rss {
    my $items;
    my $count = 0;
    foreach my $report (get_all()) {
        next unless $report->should_show();
        my $best_image = $report->get_best_picture_object();
        my $route = $report->get_route();
        next unless $best_image || $route;

        last unless ++$count <= 15; 

        my $report_url = sprintf("http://yellowleaf.org/scramble/g/r/%s",
                                 $report->get_report_page_url());

        my $image_html;
        if ($best_image) {
            $image_html = sprintf qq(<a href="%s"><img src="http://yellowleaf.org/scramble/g/r/%s"/></a>),
                $report_url,
                $best_image->get_url();
        }

        my ($yyyy, $mm, $dd) = $report->get_parsed_start_date();
        my $date = "$yyyy-$mm-${dd}T00:00:00Z";

        if (defined $route) {
            $route =~ s/^(.{250}).*/${1}.../s;
        } else {
            $route = '';
        }

        my $content = $image_html ? "<![CDATA[$image_html]]>" : $route;

        my $title = $report->get_name();
        my $filename = $report->get_filename();
        $items .= <<EOT;
    <item>
      <title>$title</title>
      <link>$report_url</link>
      <guid isPermaLink="false">$filename</guid>
      <description><![CDATA[]]></description>
      <content:encoded>$content</content:encoded>
      <dc:date>$date</dc:date>
    </item>
EOT
    }


    # http://feedvalidator.org/


    my ($sec,$min,$hour,$mday,$mon,$year) = gmtime(time);
    $year += 1900;
    $mon += 1;
    my $date = "$year-$mon-${mday}T$hour:$min:${sec}Z";
    my $xml = <<EOT;
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
 <rss version="2.0" 
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:atom="http://www.w3.org/2005/Atom"
>
  <channel>
    <title>yellowleaf.org</title>
    <atom:link href="http://yellowleaf.org/scramble/g/r/rss.xml" rel="self" type="application/rss+xml"/>
    <link>http://yellowleaf.org/scramble/g/m/home.html</link>
    <description>Gabriel's scrambling, climbing, skiing, and etceteras</description>
    <language>en-us</language>

    $items

  </channel>
</rss>
EOT

    Scramble::Misc::create("r/rss.xml", $xml);
}

sub make_reports_index_page {
    my %report_htmls;
    my $count = 0;
    my $latest_year = 0;
    foreach my $report (get_all()) {
	my ($yyyy) = $report->get_parsed_start_date();
        $latest_year = $yyyy if $yyyy > $latest_year;
	my $end = ($report->get_end_date()
		   ? sprintf(" to %s", $report->get_end_date())
		   : '');
	my $html = sprintf("<li>%s$end %s</li>",
			   $report->get_start_date(),
			   $report->get_link_html());
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
			       'html' => "<ol>$report_htmls{$id}</ol>",
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
                                                'copyright-year' => $copyright_year,
						'image-size' => '50%'));
	
    }
}

sub get_reports_for_location {
    my ($location) = @_;

    my @retval;
    foreach my $report (get_all()) {
	next if $report->is_planned();
	push @retval, $report if grep { $location->equals($_) } ($report->get_locations_visited(), $report->get_locations_attempted());
    }
    return @retval;
}

######################################################################
# end statics
######################################################################

1;
