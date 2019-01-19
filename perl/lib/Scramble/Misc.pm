package Scramble::Misc;

use strict;

use IO::File ();
use Scramble::Logger ();
use Scramble::Model::Reference ();
use Scramble::Model::List ();
use Scramble::Model::Area ();
use Scramble::Controller::ImageFragment ();
use URI::Encode ();

our $gEnableEmbeddedGoogleMap = 1;
my $gDisableGoogleMaps = 0;

our $gSiteName = 'yellowleaf.org';

#my $gDisableTopoZone = 1;
#my $gDisableTerraServerEmbedded = 1;
#my $gEnableTerraserver = 0;

=head1 Inserting links into text

The 'id' from references.xml turns into a link named by the 'name' for
the given 'id' to the 'URL' for the 'id'.

The 'id' from list names turns into a link with the 'name' from that list.

=cut
my %g_transformations;
sub make_link_transformations {
    foreach my $list (Scramble::Model::List::get_all()) {
        next unless $list->get_id;
        my $id = $list->get_id;

        my $link = $list->get_link_html;
	$g_transformations{'list'}{sprintf('\b%s\b', $id)} = _insert_links_pack($link);
    }

    foreach my $reference (Scramble::Model::Reference::get_all()) {
        my $html = eval { Scramble::Controller::ReferenceFragment::get_reference_html_with_name_only($reference) };
        next unless $html;
        my $id = $reference->get_id();
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

    my $orig_html = $html;

    # Turn this:
    # http://xxxxxxxxxxxxxx 
    # into this:
    # <a href="http://xxxxxxxxxxxxxx">http://xxxxx...</a>
    $html =~ s{\b(https?://[^\s\)]+[^\s\.\)])}{_insert_links_pack(qq(<a href="$1">) . (length($1) > 30 ? substr($1, 0, 30) . "..." : $1) . qq(</a>))}ge;

    my $key = exists $options{'type'} ? $options{'type'} : 'all';

    foreach my $regex (sort { length($b) <=> length($a) } keys %{ $g_transformations{$key} }) {
	$html =~ s/$regex/$g_transformations{$key}{$regex}/g;
    }

    $html = _insert_links_unpack($html);

    # FIXME: Deprecate most of this link insertion code.  Keep insertion of URL links.
    if ($html ne $orig_html) {
        print "Inserting deprecated link in $orig_html\n";
    }

    return "<!-- LinksInserted -->$html";
}

=head1 Formatting text

Two consecutive newlines will turn into a <p> HTML tag.

=cut
sub htmlify {
    my ($html) = @_;

    return '' unless defined $html;

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

sub make_colon_line {
    my ($title, $text) = @_;

    return '' unless $text;

    return "<b>$title: </b> $text<br>\n";
}

# FIXME: Move into Location.
sub make_location_into_path {
    my ($name) = @_;

    # breaks deprecated make_path_into_location() functionality.
    $name =~ s/\#//g;

    $name =~ s/-/--/g;
    $name =~ s/ /-/g;

    return $name;
}

sub pluralize {
    my ($number, $word) = @_;

    if ($number =~ /^\?/) {
	return "${word}s";
    }

    my $suffix = ($word =~ /s$/ ? "es" : "s");

    return $number != 1 ? "$word$suffix" : $word;
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

    my $template = Scramble::Template::create('shared/page');
    $template->param(Scramble::Template::common_params(%args),
                     enable_embedded_google_map => $args{'enable-embedded-google-map'},
                     html => $args{'html'},
                     include_header => $args{'include-header'},
                     no_title => $args{'no-title'},
                     title => $args{title});

    return $template->output();
}


sub _get_point_json {
    my (@locations) = @_;

    @locations or die "Missing locations";

    my @points;
    foreach my $location (@locations) {
        my $lat = $location->get_latitude();
        my $lon = $location->get_longitude();
        my $name = $location->get_name();
        my $link = $location->get_short_link_html();
        $link =~ s/\"/\\\"/g;
        $link =~ s/\'/\\'/g;
        push @points, qq({"lat":$lat,"lon":$lon,"name":"$name"});
    }

    return sprintf("[%s]", join(",", @points));
}
sub get_multi_point_embedded_google_map_html {
    my ($locations, $options) = @_;

    return '' if $gDisableGoogleMaps;

    my (@inputs);

    @$locations = map { $_->get_latitude() ? ($_) : () } @$locations;
    if (@$locations) {
	my $points_json = _get_point_json(@$locations);
	my $encoded_points_json = URI::Encode::uri_encode($points_json);
        push @inputs, {
            name => 'points',
            value => $points_json
        };
    }

    if ($options->{'kml-url'}) {
        my $escaped_kml_url = URI::Encode::uri_encode($options->{'kml-url'});
        push @inputs, {
            name => 'kmlUrl',
            value => "'$escaped_kml_url'"
        };
    }

    return '' unless @inputs;

    my $template = Scramble::Template::create('shared/map');
    $template->param(inputs => \@inputs);
    return $template->output();
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

    return '' unless $elevation;

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
        <div class="trip-link">$link</div>
    </figcaption>
</figure>
EOT
}
sub render_cells_into_flow {
  my ($htmls, %args) = @_;

  return '' unless @$htmls;

  # `float: left` breaks the favorite photos page.  Not having `float: left` breaks
  # photos in quad, list & location pages.
  my $float_class = $args{'float-first'} ? 'floated-flow-list' : '';

  return (qq(<ul class="flow-list $float_class">)
          . join("", map { qq(<li class="flow-list-item">$_</li>) } @$htmls)
          . "</ul>");
}

sub render_images_into_flow {
  my (%args) = @_;

  my @cells;
  push @cells, map { make_cell_html(content => $_) } @{ $args{'htmls'} || [] };
  push @cells, map {
      my $fragment = Scramble::Controller::ImageFragment->new($_);
      $fragment->create(%args)
  } @{ $args{'images'} };

  return Scramble::Misc::render_cells_into_flow(\@cells, %args);
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
