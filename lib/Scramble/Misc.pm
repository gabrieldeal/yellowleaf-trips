package Scramble::Misc;

use strict;

use IO::File ();
use Scramble::Logger ();
use Scramble::Reference ();
use Scramble::List ();
use Scramble::Area ();

our $gEnableEmbeddedGoogleMap = 1;
my $gDisableGoogleMaps = 0;

our $gSiteName = 'yellowleaf.org';

#my $gDisableTopoZone = 1;
#my $gDisableTerraServerEmbedded = 1;
#my $gEnableTerraserver = 0;
my $gEnableGoogleMaps = 0;

my $g_bullet = '&#149;&nbsp;';
my $g_amazon_associates_link = qq(<A HREF="http://www.amazon.com/exec/obidos/redirect?tag=yellowleaforg-20">In association with Amazon.</a>);

my @g_links = ({'URL' => qq(../../g/m/home.html),
		'name' => 'Trip reports',
	    },
	       {'URL' => qq(../../g/r/planned.html),
		'name' => 'Planned trips',
		'no-display' => 1,
	    },
	       {'URL' => qq(../../g/r/all.html),
		'name' => 'All trip reports',
		'no-display' => 1,
	    },
	       {'URL' => qq(../../g/m/geekery.html),
		'name' => 'Geekery',
		'no-display' => 1,
	    },
	       { URL => qq(../../g/m/pcurrent.html),
		 'name' => 'Favorite photos',
                 'no-display' => 0,
	     },
               { 'URL' => qq(../../g/li/index.html),
		 'name' => 'Peak lists',
	     },
	       { 'URL' => qq(../../g/m/quad-layout.html),
		 'name' => 'USGS quads',
		 'no-display' => 1,
	     },
	       { 'URL' => qq(../../g/m/references.html),
		 'name' => 'Links',
	     },
	       { 'URL' => qq(mailto:scramble\@yellowleaf.org),
		 'name' => 'Mail me',
	     },
	       { 'URL' => qq(../../g/a/area-index.html),
		 'name' => 'Areas',
		 'no-display' => 1,
	     },
             { 'URL' => qq(../../g/r/rss.xml),
		 'html' => 'RSS&nbsp;<img border=0 alt="" src=../../pics/rss.png>',
	     },
	       );

my $g_google_ad_javascript = <<EOT;
<script type="text/javascript"><!--
google_ad_client = "pub-1958612489793586";
google_ad_width = 120;
google_ad_height = 240;
google_ad_format = "120x240_as";
google_ad_channel ="";
google_color_border = "DFF2FD";
google_color_bg = "DFF2FD";
google_color_link = "0000CC";
google_color_url = "008000";
google_color_text = "000000";
//--></script>
<script type="text/javascript"
  src="http://pagead2.googlesyndication.com/pagead/show_ads.js">
</script>
EOT


=head1 Inserting links into text

"XXX quad" or "XXX quadrangle" turns into link named "XXX" to quad
page.  "XXX USGS quad" or "XXX USGS quadrangle" turns into link named
"XXX USGS quad" to quad page.

Location names are turned into links to the location page for that
location.

The 'id' from references.xml turns into a link named by the 'name' for
the given 'id' to the 'URL' for the 'id'.

The 'id' from list names turns into a link with the 'name' from that list.

=cut
sub get_regex { "\\b\\Q$_[0]\\E\\b" }
my %g_transformations;
sub make_link_transformations {
    foreach my $list_xml (Scramble::List::get_all_lists()) {
	next unless $list_xml->{'id'};
	my $id = $list_xml->{'id'};

	my $link = Scramble::List::make_list_link($list_xml);
	$g_transformations{'list'}{sprintf('\b%s\b', $id)} = _insert_links_pack($link);
    }
    foreach my $quad (Scramble::Area::get_all()->find('type' => 'USGS quad')) {
        next unless $quad->get_locations();
 	my $link = $quad->get_short_link_html();
	my $regex = sprintf('\b%s(\s+USGS)?\s+quad(rangle)?\b', $quad->get_id());
 	$g_transformations{'quad'}{$regex} = _insert_links_pack($link);
    }
#     foreach my $regex (Scramble::Location::get_all_regex_keys()) {
# 	my $location = Scramble::Location::get_regex_value($regex);
# 	my $link = _insert_links_pack($location->get_short_link_html());
# 	$g_transformations{'location'}{$regex} = _insert_links_pack($link);
#     }
    foreach my $area (Scramble::Area::get_all()->get_all()) {
	next if $area->get_type() eq 'USGS quad';
	my $regex = sprintf('\b%s\b', $area->get_id());
	my $link = _insert_links_pack($area->get_short_link_html());
	$g_transformations{'area'}{$regex} = $link;
    }
    foreach my $id (Scramble::Reference::get_ids()) {
	my $html = eval { Scramble::Reference::get_reference_html_with_name_only({ 'id' => $id }) };
	next unless $html;
	$id =~ s/\s+/\\s+/g;
	$g_transformations{'reference'}{$id} = _insert_links_pack($html);
    }
    my @types = keys %g_transformations;
    foreach my $type (@types) {
	foreach my $regex (keys %{ $g_transformations{$type} }) {
	    die "Duplicate id '$regex'" unless $g_transformations{$type}{$regex};
	    $g_transformations{'all'}{$regex} = _insert_links_pack($g_transformations{$type}{$regex});
	}
    }
}

# These hackey insert_*pack() functions keep the code from inserting links
# like this: <a href=mount-teneriffe-trailhead.html><a href=Mount-teneriffe.html>Mount Teneriffe</a> Trailhead</a>.
sub _insert_links_pack {
    my ($html) = @_;

    $html =~ s/(\w)(\w)/$1---NO-OP---$2---NO-OP---/g unless $html =~ /---NO-OP---/;
    $html =~ s/ /---SPACE---/g;

    return $html;
}
sub _insert_links_unpack {
    my ($html) = @_;

    $html =~ s/---NO-OP---//g;
    $html =~ s/---SPACE---/ /g;

    return $html;
}
sub insert_links {
    my ($html, %options) = @_;

    return '' unless length $html;

    # Double-inserting links can screw things up (like ---NO-OP---
    # strings are gone).
    die "Already inserted links in this" if $html =~ /LinksInserted/;

    make_link_transformations() unless keys %g_transformations;

    # Turn this:
    # http://xxxxxxxxxxxxxx 
    # into this:
    # <a href="http://xxxxxxxxxxxxxx">http://xxxxx...</a>
    $html =~ s{\b(http://[^\s\)]+[^\s\.\)])}{_insert_links_pack(qq(<a href="$1">) . (length($1) > 30 ? substr($1, 0, 30) . "..." : $1) . qq(</a>))}ge;

    my $key = exists $options{'type'} ? $options{'type'} : 'all';

    foreach my $regex (sort { length($b) <=> length($a) } keys %{ $g_transformations{$key} }) {
	$html =~ s/$regex/$g_transformations{$key}{$regex}/g;
    }

    return "<!-- LinksInserted -->" . _insert_links_unpack($html);
}

=head1 Formatting text

Two consecutive newlines will turn into a <p> HTML tag.

=cut
sub htmlify {
    my ($html) = @_;

    return unless defined $html;

    $html = insert_links($html);

    $html =~ s/---NO-OP---//g;
    $html =~ s(\n\s*\n\s*)(<p />)g;

    return $html;
}

sub dedup {
    my (@dups) = @_;

    # Preserve the order of the items in @dups.
    my %seen;
    my @deduped;
    foreach my $item (@dups) {
        push @deduped, $item unless $seen{$item};
        $seen{$item} = 1;
    }

    return @deduped;
}

sub get_links_html {
    my ($only_get_displayable) = @_;

    my @links = ($only_get_displayable
		 ? grep { ! $_->{'no-display'} } @g_links
		 : @g_links);

    my $first = shift @links;
    my $html = sprintf(qq(<a href="%s">%s</a>),
		       $first->{'URL'},
		       $first->{'name'} || $first->{'html'});
    foreach my $link (@links) {
	my $name = $link->{'name'} || $link->{'html'};
	$name =~ s/ /&nbsp;/g;
	$html .= sprintf(qq($g_bullet<a href="%s">%s</a><br>),
			 $link->{'URL'},
			 $name);
    }

    return "$html";
}

sub get_horizontal_nav_links {
    my @links = grep { ! $_->{'no-display'} } @g_links;

    my @html_links;
    foreach my $link (@links) {
	my $name = $link->{'name'};
        if (defined $name) {
            $name =~ s/ /&nbsp;/g;
        } else {
            $name = $link->{'html'};
        }
	push @html_links, sprintf(qq(<a href="%s">%s</a>),
                                  $link->{'URL'},
                                  $name);
    }
    my $html_links = join(" | ", @html_links);

    my $html = <<EOT;
<script type="text/javascript">
    function Gsitesearch(curobj){
        curobj.q.value="site:www.yellowleaf.org "+curobj.qfront.value
    }
</script>
<form action="http://www.google.com/search" method="get" onSubmit="Gsitesearch(this)">
    <table width="100%" bgcolor="DFF2FD" border=0 cellspacing=5 cellpadding=0><tr><td>
        $html_links
        &nbsp;&nbsp;
        <input name="q" type="hidden"/><input name="qfront" type="text" style="width: 180px" /><input type="submit" value="Search" />
    </td></tr></table>
</form>
EOT

    return $html;
}

# sub split_words_for_bullet_list {
#     my ($words) = @_;

#     my $max = length($g_links[0]->{'name'} || $g_links[0]->{'html'});
#     foreach my $link (@g_links) {
# 	my $len = length($link->{'name'} || );
# 	$max = $len if $len > $max;
#     }

#     my @words = split(/\s+/, $words);
#     return join("&nbsp;", @words) if length($words) < $max;

#     my @lines;
#     my $line = shift @words;
#     while(@words) {
# 	my $word = shift @words;
# 	if (length($line) + 1 + length($word) < $max) {
# 	    $line .= "&nbsp;$word";
# 	} else {
# 	    push @lines, $line;
# 	    $line = $word;
# 	}
#     }

#     return (@lines, $line);
# }
# sub make_list {
#     my ($title, @objects) = @_;

#     return '' unless @objects;

#     my %dedup = map { $_->get_id() => $_ } @objects;
#     @objects = values %dedup;
#     @objects = sort { $a->get_name() cmp $b->get_name() } @objects;

#     my @links;
#     foreach my $object (@objects) {
# 	my @split_name = Scramble::Misc::split_words_for_bullet_list($object->get_name());
# 	push @links, join("<br>&nbsp;&nbsp;",
# 			  map { $object->get_short_link_html($_) } @split_name);
#     }
#     return Scramble::Misc::make_bullet_list($title, @links);
# }
# sub make_bullet_list {
#     my ($title, @elements) = @_;

#     return (qq(<h3>$title:</h3>$g_bullet)
# 	    . join("<br>$g_bullet", @elements)
# 	    . "<p>");
# }

sub get_abbreviated_name_links {
    my (@objects) = @_;

    @objects = Scramble::Misc::dedup(@objects);
    @objects = sort { $a->get_name() cmp $b->get_name() } @objects;

    my @links;
    foreach my $object (@objects) {
	my $name = Scramble::Misc::abbreviate_name($object->get_name());
	push @links, $object->get_short_link_html($name);
    }

    return @links;
}

# sub make_into_table {
#     my ($columns, $lines) = @_;

#     die "Not supported: $columns" if $columns != 1 && $columns != 2;

#     my @lines = grep { defined $_ && length($_) > 0 } @$lines;

#     if ($columns == 1) {
# 	return join("\n", @lines);
#     } else {
# 	return sprintf(qq(<table border=0 cellspacing=5><tr><td valign="top" align="left">%s</td><td valign="top" align="left">%s</td></tr></table>),
# 		       join("\n", @lines[0 .. int(scalar(@lines)/2 + .9) - 1]),
# 		       join("\n", @lines[int(scalar(@lines)/2 + .9) .. $#lines]));
#     }
# }

sub get_pictures_img_html {
    return '';

    my (@images) = @_;

    my $icon = (2 <= scalar(grep { $_->get_rating() <= 40 } @images)
                ? "good-picture-icon.gif"
                : "picture-icon.gif");
    return qq(<img alt="(has pictures)" src="../../pics/$icon">);
}

sub remove_quad_specifier {
    my ($name) = @_;

    $name =~ s/\([^\)]+\squad\)//g;

    return $name;;
}

sub make_colon_line {
    my ($title, $text) = @_;

    return '' unless $text;

    return "<b>$title:</b> $text<br>\n";
}

sub make_location_into_path {
    my ($name) = @_;

    # breaks deprecated make_path_into_location() functionality.
    $name =~ s/\#//g;

    $name =~ s/-/--/g;
    $name =~ s/ /-/g;

    return $name;
}

sub make_path_into_location {
    my ($path) = @_;

    $path =~ s/--/HACKHACKHACK/g;
    $path =~ s/-/ /g;
    $path =~ s/HACKHACKHACK/-/g;

    return $path;
}

sub pluralize {
    my ($number, $word) = @_;

    if ($number =~ /^\?/) {
	return "${word}s";
    }

    my $suffix = ($word =~ /s$/ ? "es" : "s");

    return $number != 1 ? "$word$suffix" : $word;
}

sub get_target {
    my ($url) = @_;

    return ($url =~ /http:/ ? q( target="_top" ) : '');
}

sub make_all_internal_links_page {
    create("m/private.html", 
	   make_2_column_page("Private",
			      get_links_html()));
			      
}

sub make_usgs_quad_link {
    my ($quad, $extra) = @_;

    my $area = Scramble::Area::get_all()->find_one('id' => $quad,
						    'type' => 'USGS quad');
    return $area->get_short_link_html();
}

sub pack_name_link {
    my ($name) = @_;

    $name =~ s/\s+/_/g;

    return $name;
}

sub build_name_links {
    my ($html, $links, $name) = @_;

    if (length $$html == 0) {
	return;
    }

    $$html = qq(<a name="$name"></a>) . $$html;
    push @$links, qq(<a href="#$name">$name</a>);
}

sub make_optional_line {
    my ($format, $arg2, $arg3) = @_;

    if (ref($arg2) eq 'CODE') {
	return '' unless defined $arg3;
	my $value = $arg2->(@_[2..$#_]);
	return (defined $value ? sprintf($format, $value) : '');
    }
    
    if (! $arg3) {
	return $arg2 ? sprintf($format, $arg2) : '';
    }
    
    my ($key, $hash) = ($arg2, $arg3);
    
    if (! exists $hash->{$key}) {
	return "";
    }
    
    return sprintf($format, $hash->{$key});
}

sub make_1_column_page {
    my (%args) = @_;

    my $html = $args{'html'};
    my $footer_html = make_footer(%args);
    my $header = get_header(%args);

    my $links = '';
    if ($args{'include-header'}) {
        $links = get_horizontal_nav_links();
    }

    return <<EOT;
$header
$links

$html

$footer_html
</body>
</html>
EOT
}

sub _get_point_data {
    my (@locations) = @_;

    @locations or die "Missing locations";

    my $map_type = 'usgs';
    my $points = "[";
    foreach my $point (@locations) {
        $map_type = 'satellite' unless $point->is_in_USA();
        my $lat = $point->get_latitude();
        my $lon = $point->get_longitude();
        my $name = $point->get_name();
        my $link = $point->get_short_link_html();
        $link =~ s/\"/\\"/g;
        $link =~ s/\'/\\'/g;
        $points .= qq({ lat: $lat, lon: $lon, name: "$link" },);
    }
    $points .= "]";

    return ('points-javascript' => $points,
            'map-type' => $map_type);
}
sub get_multi_point_embedded_google_map_html {
    my ($locations, $options) = @_;

    return '' if $gDisableGoogleMaps;

    @$locations = map { $_->get_latitude() ? ($_) : () } @$locations;
    return '' unless @$locations;

    my $lat = $locations->[0]->get_latitude();
    my $lon = $locations->[0]->get_longitude();
    my $map_type = 'usgs';

    my %info = _get_point_data(@$locations);

    my $script = <<EOT;
<div id="mapContainer" style="position: relative">
    <div id="map" style="width: 335px; height: 235px"></div>
</div>
<a href="../m/usgs.html?lat=$lat&lon=$lon&type=$map_type&zoom=6">Go to the full-sized map</a>
<script type="text/javascript" src="../js/map.js"></script>
<script>
    setInput('points', $info{'points-javascript'});
    setInput('lat', '$lat');
    setInput('lon', '$lon');
    setInput('zoom', 3);
    setInput('type', '$map_type');
</script>
<p>
EOT
}

sub make_footer {
    my (%args) = @_;

    my $year;
    if (exists $args{'copyright-year'}) {
        $year = $args{'copyright-year'};
    } elsif (exists $args{'date'}) {
        ($year) = Scramble::Time::parse_date($args{'date'});
    } else {
        $year = '2004';
    }

    my @footer_html = "Copyright &copy; $year Gabriel Deal.";
    if ($args{'add-amazon-associates-html'}) {
	push @footer_html, $g_amazon_associates_link;
    }
    return sprintf(qq(<br clear="all"/><hr align=left color="black" width="90%%">%s),
                   join("<br>", @footer_html));
}

sub get_header {
  my (%options) = @_;

  my $body = qq(<body bgcolor="white">);
  my $maps_script = '';
  if ($options{'enable-embedded-google-map'}) {
    $body = qq(<body bgcolor="white" onload="ShowMeTheMap();" onunload="GUnload()">);

    $maps_script = <<EOT;
    <script src="http://maps.google.com/maps?file=api&amp;v=2&amp;key=ABQIAAAAzfKF_G3MmHWWJ8-9AKo-LhQm8q5vZmOTIOU_7tSbBBaPCrUNFBRqJJF5iDqFypI-b5NunX98iHhI2A"
      type="text/javascript"></script>
EOT
    }

  return <<EOT;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
    <title>$gSiteName $options{title}</title>
    <link rel="SHORTCUT ICON" href="../../pics/favicon.ico">
    <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
    $maps_script
  </head>
$body
EOT
}

sub make_2_column_page {
    my ($title, $middle_html, $right_html, %options) = @_;

    defined $middle_html or die "Middle HTML is not defined";

    my $ad_javascript = $options{'enable-google-ad'} ? $g_google_ad_javascript : '';
    my $left_column_content = ($options{'left-column-content'} 
			       ? $options{'left-column-content'}
			       : '');

    my $top_text = $options{'top-text'} || '';

    my $h1_title = '';
    if (! $options{'no-title'}) {
        $h1_title = exists $options{'h1-title'} ? $options{'h1-title'} : $title;
        if ($h1_title) {
            $h1_title = "<h1>$h1_title</h1>";
        }
    }

    if (! $options{'no-add-picture'}) {
	my $pic_html = Scramble::Image::get_random_picture_html('attributes' => 'align="right"');
	$middle_html = "$pic_html$middle_html";
    }

    my $footer_html = make_footer(%options);

    my ($in_table_footer_html, $after_table_footer_html, $after_table_html) = ('') x 3;
    if (exists $options{'after-table-html'}) {
	$after_table_html = $options{'after-table-html'};
	$after_table_footer_html = $footer_html;
    } else {
	$in_table_footer_html = qq(<tr valign="top" align="left"><td colspan="2">$footer_html</td></tr>);
    }

    my $bottom_two_cell_row = $options{'two-cell-row'} || $options{'bottom-two-cell-row'};
    $bottom_two_cell_row = (defined $bottom_two_cell_row
                            ? qq(<tr valign="top" align="left"><td colspan="2">$bottom_two_cell_row</td></tr>)
                            : '');

    my $top_two_cell_row = (defined $options{'top-two-cell-row'}
                            ? qq(<tr valign="top" align="left"><td colspan="2">$options{'top-two-cell-row'}</td></tr>)
                            : '');


    my $below_nav_box = $ad_javascript;
    $right_html = '' unless defined $right_html;
#     if (defined $right_html && length $right_html > 0) {
# 	$below_nav_box = $ad_javascript;
#     } else {
# 	$right_html = $ad_javascript;
#     }

    my $links = '';
    if (! $options{'no-links-box'}) {
        $links = get_horizontal_nav_links();
    }

    my $middle_column_alignment = $options{'center-middle-column'} ? 'center' : 'left';

    my $header = get_header(title => $title, %options);

    return <<EOT;
$header

$links

$h1_title
$top_text
<table width="100%" border=0 cellpadding="5">
$top_two_cell_row
<tr valign="top" align="left">
<td valign="top" align="$middle_column_alignment">
    $middle_html
</td>
<td valign="top" align="left" >
    $right_html
</td>
</tr>

$bottom_two_cell_row
$in_table_footer_html
</table>

$after_table_html
$after_table_footer_html
</body>
</html>
EOT
}

sub get_google_search_html {
    my ($value) = @_;

    $value = '' unless defined $value;
    return <<EOT;
<form><input type="submit" value=""></form>
<script type="text/javascript">
function Gsitesearch(curobj){
curobj.q.value="site:www.yellowleaf.org "+curobj.qfront.value
}
</script>
<form action="http://www.google.com/search" method="get" onSubmit="Gsitesearch(this)">
<input name="q" type="hidden"/><input name="qfront" type="text" style="width: 180px" /><input type="submit" value="Search" />
</form>
EOT

    return <<EOT;
<FORM method=GET action=http://www.google.com/custom>
<TABLE bgcolor=#FFFFFF cellspacing=0 border=0>
<tr valign=center><td>
<A HREF=http://www.google.com/search>
<IMG SRC=http://www.google.com/logos/Logo_40wht.gif border=0 ALT=Google align=middle></A>
</td>
<td>
<INPUT TYPE=text name=q size=31 maxlength=255 value="$value">
<INPUT type=submit name=sa VALUE="Google Search">
<INPUT type=hidden name=cof VALUE="S:http://www.yellowleaf.org;GL:0;AH:center;AWFID:ecb9b7112e917e77;">
</td></tr></TABLE>
</FORM>
EOT
}

sub get_images_for_locations {
    my (@locations) = @_;

    my @images = map { $_->get_picture_objects() } @locations;
    @images = Scramble::Misc::dedup(@images);

    return sort { Scramble::Image::cmp($a, $b) } @images;
}

sub get_MSN_maps_url {
    my ($lat, $lon, $datum) = @_;

    # $datum not used 

    return "http://maps.msn.com/map.aspx?L=USA&C=$lat%2c$lon&A=7.16667&P=|$lat%2c$lon|1||L1|";
# "http://maps.msn.com/(lp0jjjnvyhderb45nqsxco55)/map.aspx?L=USA&C=$lat%2c$lon&A=7.16667&P=|$lat%2c$lon|1||L1|";
}

sub get_noaa_forecast_url {
    my ($lat, $lon, $datum) = @_;

    return "http://forecast.weather.gov/MapClick.php?lat=$lat&lon=$lon&site=sew&smap=1&marine=0&unit=0&lg=en";
#    return "http://ifps.wrh.noaa.gov/cgi-bin/dwf?outFormat=Text&duration=168hr&interval=12&citylist=Select+City%2C%2Cnone&latitude=$lat&longitude=$lon&latlon=Go&ZOOMLEVEL=1&XSTART=&YSTART=&XC=&YC=&X=&Y=&siteID=SEW";;
}

sub get_google_maps_url {
    my ($lat, $lon, $datum, %options) = @_;

    return '' unless $gEnableGoogleMaps;

    return sprintf("http://maps.google.com/maps?q=%s+%s&t=h&ll=%s,%s&spn=0.116785,0.343323&t=h",
                   $lat,
                   $lon,
                   $lat,
                   $lon);
}

sub get_my_google_maps_url {
    my ($lat, $lon, $datum, %options) = @_;

    return sprintf("../../g/m/usgs.html?lon=%s&lat=%s&zoom=2&type=usgs",
                   $lon,
                   $lat);
}

# sub get_terraserver_html {
#     my ($easting, $northing, $zone) = @_;

#     return '' if $gDisableTerraServerEmbedded;
#     return '' unless defined $easting;

#     $zone =~ s/[A-Z]$//;

#     my $scale = 12;
#     my $multiplier = 800;

#     my $easting_tile = int($easting / $multiplier);
#     my $northing_tile = int($northing / $multiplier);

#     my $html = "<table border=0 cellspacing=0 cellpadding=0>\n";
#     my $format = "http://terraserver-usa.com/tile.ashx?T=2&S=$scale&X=%d&Y=%d&Z=$zone";
#     for (my $y = $northing_tile + 1; $y >= $northing_tile - 1; --$y) {
#         $html .= "<tr>";
#         foreach my $x ($easting_tile - 1 .. $easting_tile + 1) {
#             $html .= sprintf("<td><img src=$format></td>", $x, $y);
#         }
#         $html .= "</tr>\n";
#     }
#     $html .= "</table>\n";

#     return $html;
# }
# sub get_terraserver_url {
#     my ($easting, $northing, $zone) = @_;

#     return '' unless $gEnableTerraserver;
#     return '' unless defined $easting;

#     $zone =~ s/[A-Z]$//;

#     my $scale = 12;
#     my $multiplier = 800;

#     my $easting_tile = int($easting / $multiplier);
#     my $northing_tile = int($northing / $multiplier);

#     return sprintf("http://terraserver-usa.com/image.aspx?T=2&S=$scale&X=%d&Y=%d&Z=$zone",
#                    $easting_tile,
#                    $northing_tile);
# }

# sub get_topozone_url {
#     my ($lat, $lon, $datum, %options) = @_;

#     return undef if $gDisableTopoZone;

#     my $options = '';
#     if (exists $options{'scale'}) {
# 	$options .= sprintf("&s=%s", $options{'scale'} / 1000);
#     }
#     my $size = exists $options{'size'} ? $options{'size'} : 'large';
#     $options .= "&size=$size";

#     # This number determines the map datum and the coordinate system
#     # and format (UTM, DD.MM.SS, DD.DDD) displayed on the topozone
#     # page.
#     my $datum_num = { 'nad83' => 4,
# 		      'wgs84' => 4,
# 		      'nad27' => 0,
# 		  }->{lc($datum)};
#     defined $datum_num || die "Unrecognized datum '$datum'";

#     return sprintf("http://www.topozone.com/map.asp?lat=%s&lon=%s&u=$datum_num$options",
# 		   numerify($lat),
# 		   numerify($lon));
# }


sub get_peakbagger_quad_url {
    my ($quad_obj) = @_;

    my $quad = $quad_obj->get_short_name();

    $quad =~ s/Benchmark Mountain/Bench Mark Mountain/;
    $quad =~ s/ /+/g;
    $quad = Scramble::Misc::abbreviate_name($quad);

    return "http://howbert.com/cgi-bin/peaklist.pl?quadname=$quad";
}

sub abbreviate_name {
    my ($name) = @_;

    $name =~ s/\'//g;
    $name =~ s/Lake\b/Lk./;
    $name =~ s/Peak\b/Pk./;
    $name =~ s/Mountains$/Mtns./;
    $name =~ s/Mountain$/Mtn./;
    $name =~ s/^Mount\b/Mt./;

    $name =~ s/Road$/Rd./;
    $name =~ s/Avenue$/Ave./;
    $name =~ s/Street$/St./;

    return $name;
}

sub create {
    my ($path, $html) = @_;

    $path = get_output_directory() . "/g/$path";
    Scramble::Logger::verbose "Creating $path\n";
    my $ofh = IO::File->new($path, "w") 
	or die "Unable to open '$path': $!";
    $ofh->print($html) or die "Failed to write to '$path': $!";
    $ofh->close() or die "Failed to flush to '$path': $!";
}

my $g_conv_factor = .3048;
sub convert_meters_to_feet {
    my ($elevation) = @_;

    return int($elevation / $g_conv_factor);
}
sub convert_feet_to_meters {
    my ($elevation) = @_;

    return int($elevation * $g_conv_factor);
}

sub format_elevation {
    my ($elevation) = @_;

    my %details = get_elevation_details($elevation);

    my $plus = $details{'plus'} ? "+" : "";
    my $approx_str = 'approx ';
    my $approx = $details{'approximate'} ? $approx_str : '';

    my $feet = sprintf("%s$plus feet", commafy($details{feet}));
    my $meters = sprintf("%s$plus meters", commafy($details{meters}));

#    if ($details{'units'} eq 'meters') {
#        return "$approx$meters ($approx_str$feet)";
#    } else {
#        return "$approx$feet ($approx_str$meters)";
#    }

    return "$approx$feet";
}

sub get_elevation_details {
    my ($elevation) = @_;

    my $orig_elev = $elevation;

    my $approx = ($elevation =~ s/^~//
                  ? 1
                  : 0);

    my $units = ($elevation =~ s/ (m|meters)$//
                 ? 'meters'
                 : 'feet');

    my $plus = ($elevation =~ s/\+\s*$//
                ? 1
                : 0);

    die "bad elevation '$orig_elev'" unless $elevation =~ /^-?\d+$/;

    my $meters;
    my $feet;
    if ($units eq 'meters') {
        $meters = $elevation;
        $feet = convert_meters_to_feet($elevation);
    } elsif ($units eq 'feet') {
        $meters = convert_feet_to_meters($elevation);
        $feet = $elevation;
    } else {
        die "Unrecognized elevation units '$units'";
    }

    return ('approximate' => $approx,
            'plus' => $plus,
            'units' => $units,
            'meters' => $meters,
            'feet' => $feet,
            'elevation' => $elevation);
}

sub format_elevation_short {
    my ($elevations) = @_;

    my @formatted_elevations;
    foreach my $elevation (split(/, */, $elevations)) {
        my %details = get_elevation_details($elevation);
        push(@formatted_elevations,
             sprintf("%s%s%s%s",
                     $details{'approximate'} ? 'approx ' : '',
                     commafy($details{'feet'}),
                     "'",
                     $details{'plus'} ? '+' : ''));
    }

    return join ", ", @formatted_elevations;
}


######################################################################
# Config

my $g_output_directory;
sub get_output_directory { $g_output_directory }
sub set_output_directory { $g_output_directory = $_[0] }

######################################################################

sub numerify_longitude {
    my ($lon) = @_;

    if ($lon =~ /^-\d+\.\d+$/) {
	return $lon;
    } elsif ($lon =~ /^(\d+\.\d+) (E|W)$/) {
	return $2 eq 'W' ? -$1 : $1;
    } else {
	die "Unable to parse longitude '$lon'";
    }
}

sub numerify_latitude {
    my ($lat) = @_;

    my ($num, $hemisphere);
    if (($num, $hemisphere) = ($lat =~ /^(\d+\.\d+) (N|S)$/)) {
        return $hemisphere eq 'S' ? -$num : $num;
    } elsif ($lat =~ /^-?\d+\.\d+$/) {
        return $lat
    } else {
        die "Unable to parse latitude '$lat'";
    }
}

sub numerify {
    my ($string) = @_;

    my $orig_str = $string;
    $string =~ s/^~//; # elevation
    $string =~ s/,//g; # elevation
    $string =~ s/ m$//; # elevation
    $string =~ s/\+$//; # elevation

    $string =~ s/\s+\((approx )?[\d,]+ meters\)$//; # elevation
    $string =~ s/\s+feet//; # elevation

    $string =~ s/ N$//; # latitude
    $string =~ s/^(\d+\.\d+) W/-$1/; # longitude

    die "Can't numerify '$orig_str': $string" unless $string =~ /^-?\d+(\.\d+)?( m)?$/;

    return $string;
}

sub commafy {
    my ($number) = @_;
    1 while $number =~ s/(\d)(\d\d\d)(,|$)/$1,$2/g;
    return $number;					 
}

sub make_cell_html {
  my ($contents_html, $caption) = @_;

  my $caption_html = '';
  if ($caption) {
    $caption_html = qq(<caption align="bottom" style="text-align: left">$caption</caption>);
  }

  return <<EOT;
<table border="0" style="display: inline-block; vertical-align: text-top;">
    $caption_html
    <tr>
        <td>$contents_html</td>
    </tr>
</table>
EOT
}
sub render_cells_into_flow {
  my ($htmls) = @_;

  # The first one needs to float left because it is likely to be a large table.
  # Floating all the rest left causes odd display in IE.
  return (qq(<ul style="padding: 0; margin: 0;">\n)
	  . qq(    <li style="float: left; display: inline-block; padding: 5px;">)
	  . join(qq(</li>\n    <li style="display: inline-block; padding: 5px;">), @$htmls)
	  . "</li>\n"
	  . "</ul>");
}

sub render_images_into_flow {
  my (%args) = @_;

  my @cells;
  push @cells, map { make_cell_html($_) } @{ $args{'htmls'} || [] };
  push @cells, map { $_->get_html('no-report-link' => $args{'no-report-link'}) } @{ $args{'images'} };

  return Scramble::Misc::render_cells_into_flow(\@cells);
}

1;
