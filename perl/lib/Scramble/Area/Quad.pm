package Scramble::Area::Quad;

use strict;

use Scramble::Area ();

our @ISA = qw(Scramble::Area);
my @gLayouts;

sub new {
    my $arg0 = shift;
    my ($self) = @_;

    my $short_name = $self->get_name();

    $self->{'name'} = $short_name . " USGS quad";
    $self->{'short-name'} = $short_name;
    bless($self, ref($arg0) || $arg0);

    $self->_set_required(qw(short-name));
    $self->_set_optional(qw(corner-id no-lat-lon datum));


    if (defined(my $lat = $self->_get_optional("upper-left-latitude"))) {
	my $lon = $self->_get_optional("upper-left-longitude");
	$self->{'ul-lat'} = Scramble::Misc::numerify_latitude($lat);
	$self->{'ul-lon'} = Scramble::Misc::numerify_longitude($lon);
    }

    return $self;
}

sub get_short_name { $_[0]->{'short-name'} }
sub get_corner_id { $_[0]->{'corner-id'} }
sub get_map_datum { $_[0]->{"datum"} }
sub set_map_datum { 
    my $self = shift;
    my ($datum) = @_;

    if (defined $self->get_map_datum() && $datum ne $self->get_map_datum()) {
	die sprintf("Map datum mismatch '%s' and '%s'",
		    $datum,
		    $self->get_map_datum());
    }

    $self->set("datum", $datum);
}

sub get_upper_left_latitude { $_[0]->{'ul-lat'} }
sub get_upper_left_longitude { $_[0]->{'ul-lon'} }
sub set_upper_left_longitude {
    my $self = shift;
    my ($lon) = @_;

    if (defined(my $expected = $self->get_upper_left_longitude())) {
	if ($expected != $lon) {
	    die sprintf("'%s' given longitude '$lon' expected '$expected'", $self->get_name());
	}

	return;
    }
    $self->{'ul-lon'} = $lon;
}
sub set_upper_left_latitude {
    my $self = shift;
    my ($lat) = @_;

    if (defined(my $expected = $self->get_upper_left_latitude())) {
	if ($expected != $lat) {
	    die "Given latitude '$lat' expected '$expected'";
	}

	return;
    }
    $self->{'ul-lat'} = $lat;
}

sub get_download_id { 
    my $self = shift;

    my $id = $self->_get_optional('download-id');
    return $id if defined $id;

    return $self->in_washington() ? 'WAUWUSGSQuads' : undef;
}

sub get_neighboring_quad_object {
    my $self = shift;
    my ($dir) = @_;

    my $id = $self->get_neighboring_quad_id($dir);
    return undef unless defined $id;
    return eval { Scramble::Area::get_all()->find_one('id' => $id) };
}
sub get_neighboring_quad_id { $_[0]->_get_optional($_[1]) }
sub add_neighboring_quad_id {
    my $self = shift;
    my ($dir, $quad_id) = @_;

    my $existing_quad_id = $self->get_neighboring_quad_id($dir);
    if ($existing_quad_id && $existing_quad_id ne $quad_id) {
	die $self->get_id() . " quad mismatch to $dir, currently have '$existing_quad_id', given '$quad_id'";
    }

    $self->{$dir} = $quad_id;
}
sub has_neighbors {
    my $self = shift;

    foreach my $dir (qw(east west south north)) {
	return 1 if $self->get_neighboring_quad_id($dir);
    }

    return 0;
}

sub get_quad_link {
    my $self = shift;
    my ($dir1, $dir2) = @_;

    my $link = $self->_get_quad_link($dir1, $dir2);
    if (! $link && $dir2) {
	$link = $self->_get_quad_link($dir2, $dir1);
    }
    return $link;
}
sub _get_quad_link {
    my $self = shift;
    my ($direction, $direction2) = @_;

    my $quad_id = $self->get_neighboring_quad_id($direction);
    return undef unless $quad_id;
    my $quad = eval { Scramble::Area::get_all()->find_one('id' => $quad_id) };
    if (! $quad) {
	return $direction2 ? undef : $quad_id;
    }
    if (! $direction2) {
	return $quad->get_short_link_html($quad->get_short_name());
    }

    return $quad->_get_quad_link($direction2);
}

sub get_misc_html {
    my $self = shift;

    my $download_at = '';
    if ($self->get_download_id()) {
	my $reference = Scramble::Reference::get_reference_for_id($self->get_download_id());
	$download_at
	    = Scramble::Misc::make_colon_line("Download at",
					      Scramble::Reference::get_reference_html_with_name_only($reference));
    }

    my $neighbor_quads = '';
    if ($self->has_neighbors()) {
	$neighbor_quads = sprintf("<h2>Neighboring Quads</h2> <table cellspacing=0 cellpadding=10 border=1>"
				  . "<tr><td>%s</td> <td>%s</td> <td>%s</td></tr>"
				  . "<tr><td>%s</td> <td>%s</td> <td>%s</td></tr>"
				  . "<tr><td>%s</td> <td>%s</td> <td>%s</td></tr></table>",
				  $self->get_quad_link('north', 'west') || '&nbsp;',
				  $self->get_quad_link('north') || '&nbsp;',
				 $self->get_quad_link('north', 'east') || '&nbsp;',
				  $self->get_quad_link('west') || '&nbsp;',
				  $self->get_short_name(),
				  $self->get_quad_link('east') || '&nbsp;',
				  $self->get_quad_link('south', 'west') || '&nbsp;',
				  $self->get_quad_link('south') || '&nbsp;',
				  $self->get_quad_link('south', 'east') || '&nbsp;');
    }
    my $peakbagger_html = '';
    if ($self->in_washington()) {
        my $url = Scramble::Misc::get_peakbagger_quad_url($self);
	$peakbagger_html = Scramble::Misc::make_colon_line("See the peaks on this quad at",
							   qq(<a href="$url">Northwest Peakbagger\'s Asylum</a>));
    }

    return <<EOT;
$download_at
$peakbagger_html

$neighbor_quads
EOT
}

######################################################################
# Static
######################################################################

sub init {
    for (my $i = 1; 
	 my $corner = eval { Scramble::Area::get_all()->find_one('isa' => __PACKAGE__,
								 'type' => 'USGS quad',
								 'corner-id' => $i) }; 
	 ++$i) 
    {
	my $array = [];
	_init($corner, $array);
	push @gLayouts, $array;
    }

    foreach my $array (@gLayouts) {
        for (my $x = 0; $x < @$array; ++$x) {
            for (my $y = 0; $y < @{ $array->[$x] }; ++$y) {
                my $quad = $array->[$x][$y];
                next unless defined $quad;
                if ($array->[$x + 1] && $array->[$x + 1][$y]) {
                    $quad->add_neighboring_quad_id('south', $array->[$x + 1][$y]->get_id());
                }
                if ($x > 0 && $array->[$x - 1] && $array->[$x - 1][$y]) {
                    $quad->add_neighboring_quad_id('north', $array->[$x - 1][$y]->get_id());
                }
                if ($array->[$x][$y+1]) {
                    $quad->add_neighboring_quad_id('east', $array->[$x][$y + 1]->get_id());
                }
                if ($y > 0 && $array->[$x][$y - 1]) {
                    $quad->add_neighboring_quad_id('west', $array->[$x][$y - 1]->get_id());
                }
            }
        }
    }
}
sub _init {
    my ($corner, $layout) = @_;

    make_layout_array($corner, 0, 0, $layout);

    # add lat/lon to all quads
    die sprintf("Missing lat/lon in '%s'", $corner->get_name()) 
	unless defined $corner->get_upper_left_latitude();
    my $lat = Scramble::Misc::numerify($corner->get_upper_left_latitude());
    my $lon = Scramble::Misc::numerify($corner->get_upper_left_longitude());
    my $increment = 7.5 / 60;
    my $datum = $corner->get_map_datum();
    for (my $x = 0; $x < @$layout; ++$x) {
	for (my $y = 0; $y < @{ $layout->[$x] }; ++$y) {
	    next unless defined $layout->[$x][$y];
	    $layout->[$x][$y]->set_upper_left_latitude($lat - $x * $increment);
	    $layout->[$x][$y]->set_upper_left_longitude($lon + $y * $increment);
	    $layout->[$x][$y]->set_map_datum($datum);
	}
    }
}

sub make_layout_array {
    my ($quad, $x, $y, $array) = @_;

    if ($x < 0 or $y < 0) {
	die "Went off edge of array: $x, $y from ", $quad->get_name();
    }

    if ($array->[$y][$x] && $array->[$y][$x]->get_id() ne $quad->get_id()) {
	die sprintf("Inconsistant, expected '%s', got '%s'",
		    $array->[$y][$x]->get_id(),
		    $quad->get_id());
    }
    return if $x < 0 || $y < 0 || $array->[$y][$x];
    
    $array->[$y][$x] = $quad;
    my $neighbor;
    if ($neighbor = $quad->get_neighboring_quad_object('east')) {
	make_layout_array($neighbor, $x+1, $y, $array);
    }
    if ($neighbor = $quad->get_neighboring_quad_object('south')) {
	make_layout_array($neighbor, $x, $y+1, $array);
    }
    if ($neighbor = $quad->get_neighboring_quad_object('west')) {
	make_layout_array($neighbor, $x-1, $y, $array);
    }
    if ($neighbor = $quad->get_neighboring_quad_object('north')) {
	make_layout_array($neighbor, $x, $y-1, $array);
    }
}

1;
