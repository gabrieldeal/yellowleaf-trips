package Scramble::Misc;

use strict;

use IO::File ();
use Scramble::Logger ();
use Scramble::Reference ();
use Scramble::List ();
use Scramble::Area ();
use URI::Encode ();

our $gEnableEmbeddedGoogleMap = 1;
my $gDisableGoogleMaps = 0;

our $gSiteName = 'yellowleaf.org';

#my $gDisableTopoZone = 1;
#my $gDisableTerraServerEmbedded = 1;
#my $gEnableTerraserver = 0;

my $g_bullet = '&#149;&nbsp;';
my $g_amazon_associates_link = qq(<A HREF="https://www.amazon.com/exec/obidos/redirect?tag=yellowleaforg-20">In association with Amazon.</a>);

my @g_links = ({'URL' => qq(../../g/m/home.html),
		'name' => 'Trips',
	    },
               { URL => qq(../../g/m/pcurrent.html),
		 'name' => 'Favorite photos',
             },
               { 'URL' => qq(../../g/li/index.html),
		 'name' => 'Peak lists',
	     },
               { 'URL' => qq(../../g/m/references.html),
		 'name' => 'References',
	     },
	       { 'URL' => qq(mailto:scramble\@yellowleaf.org),
                 'name' => 'Contact',
	     },
               );

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
    $html =~ s{\b(https?://[^\s\)]+[^\s\.\)])}{_insert_links_pack(qq(<a href="$1">) . (length($1) > 30 ? substr($1, 0, 30) . "..." : $1) . qq(</a>))}ge;

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

sub get_horizontal_nav_links {
    my @html_links;
    foreach my $link (@g_links) {
	my $name = $link->{'name'};
        if (defined $name) {
            $name =~ s/ /&nbsp;/g;
        } else {
            $name = $link->{'html'};
        }
        push @html_links, sprintf(qq(<a class="nav-link nav-item text-dark" href="%s">%s</a>),
                                  $link->{'URL'},
                                  $name);
    }

    my $html = <<EOT;
<script type="text/javascript">
    function Gsitesearch(curobj){
        curobj.q.value="site:www.yellowleaf.org "+curobj.qfront.value
    }
</script>
<nav class="navbar navbar-expand-lg navbar-light custom-navbar" style="background-color: #DFF2FD;">
  <button class="navbar-toggler"
          type="button"
          data-toggle="collapse"
          data-target="#navbarSupportedContent"
          aria-controls="navbarSupportedContent"
          aria-expanded="false"
          aria-label="Toggle navigation">
    <span class="navbar-toggler-icon"></span>
  </button>

  <div class="collapse navbar-collapse" id="navbarSupportedContent">
    <div class="navbar-nav mr-auto">
        @html_links
    </div>
    <form class="form-inline my-2 my-lg-0"
          id="navbar"
          action="https://www.google.com/search"
          method="get"
          onSubmit="Gsitesearch(this)">
        <input name="q" type="hidden">
        <input name="qfront" class="form-control mr-sm-2" type="search" placeholder="Search" aria-label="Search">
        <button class="btn btn-outline-success my-2 my-sm-0" type="submit">Search</button>
    </form>
</nav>
EOT

    return $html;
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

    return ($url =~ /https?:/ ? q( target="_top" ) : '');
}

sub make_usgs_quad_link {
    my ($quad, $extra) = @_;

    my $area = Scramble::Area::get_all()->find_one('id' => $quad,
						    'type' => 'USGS quad');
    return $area->get_short_link_html();
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
    my $header = get_header(%args);

    my $footer_html = make_footer(%args);

    my $links = '';
    if ($args{'include-header'}) {
        $links = get_horizontal_nav_links();
    }

    my $title = '';
    if ($args{title}) {
        $title = qq(<h1>$args{title}</h1>);
    }

    return <<EOT;
$header
$links

<div style="margin: 5px">
    $title
    $html
</div>

$footer_html
</body>
</html>
EOT
}

sub _get_point_json {
    my (@locations) = @_;

    @locations or die "Missing locations";

    my @points;
    foreach my $point (@locations) {
        my $lat = $point->get_latitude();
        my $lon = $point->get_longitude();
        my $name = $point->get_name();
        my $link = $point->get_short_link_html();
        $link =~ s/\"/\\\"/g;
        $link =~ s/\'/\\'/g;
        push @points, qq({"lat":$lat,"lon":$lon,"name":"$name"});
    }

    return sprintf("[%s]", join(",", @points));
}
sub get_multi_point_embedded_google_map_html {
    my ($locations, $options) = @_;

    return '' if $gDisableGoogleMaps;

    my (%small_map_params, @large_map_params);

    @$locations = map { $_->get_latitude() ? ($_) : () } @$locations;
    if (@$locations) {
	my $points_json = _get_point_json(@$locations);
	my $encoded_points_json = URI::Encode::uri_encode($points_json);
	$small_map_params{points} = $points_json;
	push @large_map_params, "points=$encoded_points_json";
    }

    if ($options->{'kml-url'}) {
	my $kml_url = URI::Encode::uri_encode($options->{'kml-url'});
	push @large_map_params, "kmlUrl=$kml_url";
	$small_map_params{kmlUrl} = "'$kml_url'";
    }

    return '' unless @large_map_params;

    my $large_map_params = join("&", @large_map_params);
    my $small_map_javascript = join("\n", map { qq(Yellowleaf.Map.setInput('$_', $small_map_params{$_});) } keys %small_map_params);

    my $script = <<EOT;
<div id="mapContainer" style="position: relative">
    <div id="map" style="width: 333px; height: 250px"></div>
</div>
<a href="../m/usgs.html?$large_map_params">Larger map</a>
<script>
    Yellowleaf.Map.initializeOnLoad();
    $small_map_javascript
</script>
<p>
EOT
}

sub make_lightbox_html {
    return <<EOT;
    <div id="blueimp-gallery" class="custom-blueimp blueimp-gallery blueimp-gallery-controls">
      <div class="slides"></div>
      <h3 class="title"></h3>
      <a class="prev">‹</a>
      <a class="next">›</a>
      <a class="close">×</a>
      <a class="play-pause"></a>
      <ol class="indicator"></ol>
    </div>

    <script type="text/javascript">
      Yellowleaf.Lightbox.initialize();
    </script>
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

    my $copyright = $args{copyright} || 'Gabriel Deal';
    my @footer_html = "Copyright &copy; $year $copyright.";
    if ($args{'add-amazon-associates-html'}) {
	push @footer_html, $g_amazon_associates_link;
    }

    push @footer_html, make_lightbox_html();

    my $footer_html = join("<br>", @footer_html);

    return <<EOT;
        <br clear="all" />
        <hr align=left color="black" width="90%%" />
        $footer_html
EOT
}

sub get_header {
  my (%options) = @_;

  my $body = qq(<body style="width: 100%; margin: 0" bgcolor="#f6f6f6">);

  my $maps_script = '';
  if ($options{'enable-embedded-google-map'}) {
    $body = qq(<body style="width: 100%; margin: 0" bgcolor="#f6f6f6">);

    $maps_script = <<EOT;
<script type="text/javascript"
        src="https://maps.googleapis.com/maps/api/js?v=3&key=AIzaSyAL-uATrgEqPxb9sGCq4QFKnBOSwSaKC5g&sensor=false">
</script>
EOT
    }

    my $google_analytics_script = <<'EOM';
<script type="text/javascript">
  var _gaq = _gaq || [];
  _gaq.push(['_setAccount', 'UA-30591814-1']);
  _gaq.push(['_trackPageview']);

  (function() {
    var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
    ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
    var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
  })();
</script>
EOM

  return <<EOT;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html lang="en">
<head>
    <title>$options{title}</title>
    <link rel="SHORTCUT ICON" href="../../pics/favicon.ico">
    <meta http-equiv="content-type" content="text/html; charset=utf-8"/>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <link rel="stylesheet" type="text/css" href="../css/site.css" />
    $maps_script
    $google_analytics_script
    <script type="text/javascript" src="../js/main.js"></script>
    <script type="text/javascript" src="../js/async.js" async></script>
  </head>
$body
EOT
}

sub make_2_column_page {
    my ($title, $middle_html, $right_html, %options) = @_;

    defined $middle_html or die "Middle HTML is not defined";

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


    $right_html = '' unless defined $right_html;

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

sub get_images_for_locations {
    my (@locations) = @_;

    my @images = map { $_->get_picture_objects() } @locations;
    @images = Scramble::Misc::dedup(@images);

    return sort { Scramble::Image::cmp($a, $b) } @images;
}

sub get_my_google_maps_url {
    my ($lat, $lon, $datum, %options) = @_;

    return sprintf("../../g/m/usgs.html?lon=%s&lat=%s&zoom=2&type=usgs",
                   $lon,
                   $lat);
}

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

sub slurp {
    my ($path) = @_;

    return do {
        open(my $fh, $path) or die "Can't open $path: $!";
        local $/ = undef;
        <$fh>;
    };
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
  my (%args) = @_;

  my $contents_html = $args{content} || die "Missing 'content' argument";
  my $description = $args{description} || '';
  my $link = $args{link} || '';

  return <<EOT;
<figure style="display: table;">
    $contents_html
    <figcaption style="display: table-caption; caption-side: bottom ;">
        <div class="cell-description">$description</div>
        <div class="report-link">$link</div>
    </figcaption>
</figure>
EOT
}
sub render_cells_into_flow {
  my ($htmls, %opts) = @_;

  return '' unless @$htmls;

  return (qq(<ul class="flow-list">)
          . join("", map { qq(<li class="flow-list-item">$_</li>) } @$htmls)
          . "</ul>");
}

sub render_images_into_flow {
  my (%args) = @_;

  my $no_float_first = delete $args{'no-float-first'};

  my @cells;
  push @cells, map { make_cell_html(content => $_) } @{ $args{'htmls'} || [] };
  push @cells, map { $_->get_html(%args)
		 } @{ $args{'images'} };

  return Scramble::Misc::render_cells_into_flow(\@cells, 'no-float-first' => $no_float_first);
}

sub sanitize_for_filename {
    my ($filename) = @_;

    $filename =~ s/[^\w\.]//g;

    return $filename;
}

sub choose_interactive {
    my @choices = @_;

    die "No choices given" unless @choices;

    foreach my $i (0 .. $#choices) {
        print qq[$i) $choices[$i]{name}\n];
    }

    my $chosen_index;
    do {
        print "Which? ";
        chomp($chosen_index = <STDIN>);
    } while ($chosen_index !~ /^\d+$/ || $chosen_index < 0 || $chosen_index > $#choices);

    return $choices[$chosen_index]{value}
}

1;
