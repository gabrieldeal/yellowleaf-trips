package Scramble::Model::List;

use strict;

use Scramble::Misc;
use Scramble::Model;
use Scramble::Page::ImageFragment ();
use Scramble::Logger;

my @g_lists;
sub get_all_lists {
    return @g_lists;
}

sub get_location_xmls { @{ $_[0]->{'location'} } }

sub get_sortby {
    my ($list_xml) = @_;

    return $list_xml->{'sortby'};
}

sub get_id {
    my ($list_xml, $sortby) = @_;

    defined $list_xml->{'id'} or die "Missing ID";
    my $id = $list_xml->{'id'};
    if (defined $sortby) {
	$id .= $sortby;
    } elsif (exists $list_xml->{'sortedby'}) {
	$id .= $list_xml->{'sortedby'};
    }

    return $id;
}

sub location_equals {
    my ($a, $b) = @_;

    return ($a->{'name'} eq $b->{'name'}
            && $a->{'quad'} eq $b->{'quad'}
            && (! $a->{'county'}
                || $a->{'county'} eq $b->{'county'}));
}

sub new_sorted_list {
    my ($old_list, $sortby) = @_;

    my %new_list = %$old_list;
    $new_list{'location'} = [ map { { %$_ } } @{ $old_list->{'location'} } ];
    $new_list{'location'} = [ sort({ sort_list($sortby, $a, $b) } @{ $new_list{'location'} }) ];
    $new_list{'sortedby'} = $sortby;

    # Now that it is sorted, remove duplicate locations from the list:
    for (my $i = 0; $i + 1 < @{ $new_list{'location'} }; ++$i) {
        my $cur = $new_list{'location'}[$i];
        my $next = $new_list{'location'}[$i+1];
        if (location_equals($cur, $next)) {
            splice(@{ $new_list{'location'} }, $i + 1, 1);
            $i--;
        }
    }

    my $count = 1;
    map { $_->{'order'} = $count++ } @{ $new_list{'location'} };

    return \%new_list;
}
sub open {
    my (@paths) = @_;
    
    @g_lists = Scramble::Model::open_documents(@paths);
    @g_lists or die "No lists";

    for (my $i = 0; $i < @g_lists; ++$i) {
	Scramble::Logger::verbose "Processing $g_lists[$i]{'name'}\n";
	next unless exists $g_lists[$i]{'sortby'};
	
	my $sortby = get_sortby($g_lists[$i]);
	my $new_list = new_sorted_list($g_lists[$i], $sortby);
	splice(@g_lists, $i, 1, $new_list);
    }
    for (my $i = 0; $i < @g_lists; ++$i) {
        $g_lists[$i]{'internal-URL'} = sprintf("../%s",
                                               get_list_path($g_lists[$i]));
	next if exists $g_lists[$i]{'URL'};
	$g_lists[$i]{'URL'} = $g_lists[$i]{'internal-URL'};
    }
}

sub sort_list {
    my ($by, $l1, $l2) = @_;

    if ($by eq 'elevation') {
        my %e1 = Scramble::Misc::get_elevation_details(get_elevation($l1));
        my %e2 = Scramble::Misc::get_elevation_details(get_elevation($l2));
	return $e2{feet} <=> $e1{feet};
    } elsif ($by eq 'MVD') {
        return $l2->{'MVD'} <=> $l1->{'MVD'};
    } else {
	die "Not implemented '$by'";
    }
}

sub get_location_object {
    my ($list_location) = @_;

    my $name = $list_location->{'name'};
    return undef unless $name;

    if (! exists $list_location->{'object'}) {
	$list_location->{'object'} =  eval { 
	    Scramble::Model::Location::find_location('name' => $name,
                                                     'quad' => $list_location->{'quad'},
                                                     'include-unvisited' => 1);
	  };
    }
    return $list_location->{'object'};
}

sub get_is_unofficial_name {
    my ($list_location) = @_;

    my $location = get_location_object($list_location);
    if ($location) {
	return $location->get_is_unofficial_name();
    }

    return $list_location->{'unofficial-name'};
}

sub get_elevation {
    my ($list_location) = @_;

    local $Data::Dumper::Maxdepth = 2;

    my $location = get_location_object($list_location);
    if ($location) {
	return $location->get_elevation() || die "No elevation: " . Data::Dumper::Dumper($list_location);
    }

    return $list_location->{'elevation'} || die "No elevation: " . Data::Dumper::Dumper($list_location);
}

sub get_aka_names {
    my ($list_location) = @_;
    
    my $location = get_location_object($list_location);
    if ($location) {
	return join(", ", $location->get_aka_names());
    }

    return $list_location->{'AKA'};
}

sub get_list_path {
    my ($list_xml, $sortby) = @_;

    return sprintf("li/%s.html",
		   Scramble::Misc::make_location_into_path(get_id($list_xml, $sortby)));
}


sub make_list_link {
    my ($list_xml) = @_;

    return sprintf(qq(<a %s href="%s">%s</a>),
		   Scramble::Misc::get_target($list_xml->{'URL'}),
		   $list_xml->{'URL'},
		   $list_xml->{'name'});
}

sub get_location_link_html {
    my (%args) = @_;

    return eval { 
	my $location = Scramble::Model::Location::find_location(%args);
	return $location->get_short_link_html();
    } || $args{'name'};
}

sub get_cell_value {
    my ($name, $list_location) = @_;

    if ($name eq 'name') {
	return (get_location_link_html('name' => $list_location->{'name'},
				       'quad' => $list_location->{'quad'})
		. (get_is_unofficial_name($list_location) ? "*" : '')
		. Scramble::Misc::make_optional_line(" (AKA %s)",
						     get_aka_names($list_location)));
    } elsif ($name eq 'elevation') {
	return Scramble::Misc::format_elevation_short(get_elevation($list_location));
    } elsif ($name eq 'quad') {
        return '' unless $list_location->{'quad'};
        my $quad = eval { Scramble::Model::Area::get_all()->find_one('id' => $list_location->{'quad'},
                                                                     'type' => 'USGS quad') };
        return $list_location->{'quad'} unless $quad;
        return $quad->get_short_name();
    } elsif ($name eq 'description') {
	return Scramble::Misc::insert_links($list_location->{$name});
    } elsif ($list_location->{$name}) {
	return $list_location->{$name};
    } else {
	return "";
    }
}
my %gCellTitles = ('name' => 'Location Name',
		   'elevation' => 'Elevation',
		   'quad' => 'USGS quad',
		   'description' => 'name',
		   );
sub get_cell_title { return $gCellTitles{$_[0]} || ucfirst($_[0]) }

sub make_google_kml {
    my ($list_xml) = @_;

    my $xml = <<EOT;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://earth.google.com/kml/2.1">
EOT
    foreach my $list_location (@{ $list_xml->{'location'} }) {
        my $location = get_location_object($list_location);
        if (! $location) {
            next;
        }
        my $name = $location->get_name();
        my $lat = $location->get_latitude();
        if (! defined $lat) {
            next;
        }
        my $lon = $location->get_longitude();
        $xml .= <<EOT;
  <Placemark>
    <name>$name</name>
    <description>$name</description>
    <Point>
      <coordinates>$lon,$lat</coordinates>
    </Point>
  </Placemark>
EOT
    }

    $xml .= "</kml>";

    my $file = Scramble::Misc::make_location_into_path(get_id($list_xml, ''));
    Scramble::Misc::create("li/$file.xml", $xml);
}

sub get_images_to_display_for_locations {
    my (%args) = @_;

    my $max_images = $args{'max-images'};
    my $locations = $args{'locations'};

    my @images;
    foreach my $location (@$locations) {
      my @location_images = $location->get_picture_objects();
      @location_images = sort { Scramble::Model::Image::cmp($a, $b) } @location_images;
      push @images, $location_images[0] if @location_images;
    }

    @images = Scramble::Misc::dedup(@images);
    @images = sort { Scramble::Model::Image::cmp($a, $b) } @images;
    if (@images > $max_images) {
	@images = @images[0..$max_images-1];
    }

    return @images;
}

sub make_list_page {
    my ($list_xml) = @_;

    my @location_objects;
    my $county = $list_xml->{'location'}[0]{'county'};

    my @column_names = qw(order name elevation quad);
    if ($list_xml->{'columns'}) {
	@column_names = split(/,\s*/, $list_xml->{'columns'});
    }

    my $locations_html = <<EOT;
<style type="text/css">
th.list, td.list {
    padding: 5px;
}
table.list, th.list, td.list {
    border: 2px solid black;
}
table.list {
    border-collapse: collapse;
}
</style>

<table class="list">
    <tr class="list">
EOT
    foreach my $column_name (@column_names) {
	$locations_html .= sprintf(qq(<th class="list">%s</th>), get_cell_title($column_name));
    }
    $locations_html .= "</tr>";
    foreach my $list_location (@{ $list_xml->{'location'} }) {
	my $location_object = get_location_object($list_location);
	if ($location_object) {
	    push @location_objects, $location_object;
	}

	$locations_html .= qq(<tr class="list">);
	foreach my $column_name (@column_names) {
	    $locations_html .= sprintf(qq(<td class="list">%s</td>), get_cell_value($column_name, $list_location));
	}
	$locations_html .= "</tr>";
    }
    $locations_html .= "</table>";

    my $note = Scramble::Misc::make_optional_line("%s<p>", 
						  \&Scramble::Misc::htmlify,
						  $list_xml->{'content'});
    my $max_images = @{ $list_xml->{'location'} } / 6;
    if ($max_images < 10) {
        $max_images = 10;
    }
$max_images = 100;

    my @images = get_images_to_display_for_locations('locations' => \@location_objects,
						     'max-images' => $max_images);
    my @image_fragments = map { Scramble::Page::ImageFragment->new($_) } @images;
    my @image_htmls = map { Scramble::Misc::make_cell_html(content => $_->create()) } @image_fragments;
    my $images_html = Scramble::Misc::render_cells_into_flow([ $locations_html, @image_htmls ],
                                                             'float-first' => 1);

    my $title = $list_xml->{'name'};

    my $html = <<EOT;
$note
$images_html
EOT

    Scramble::Misc::create(get_list_path($list_xml), 
			   Scramble::Misc::make_1_column_page(title => $title,
							      html => $html,
							      'include-header' => 1));
}

sub make_lists {
    my $index_html;
    foreach my $list_xml (get_all_lists()) {
        if ($list_xml->{'skip'}) {
            next;
        }
	if (! $list_xml->{'no-display'}) {
	    $index_html .= sprintf(qq(<li>%s</li>), make_list_link($list_xml));
	} elsif ($list_xml->{'URL'}) {
            $index_html .= sprintf(qq(<li><a href="%s">%s</li>), 
                                   $list_xml->{URL},
                                   $list_xml->{name});
        }
			
        Scramble::Logger::verbose("Making $list_xml->{name} list\n");
	make_list_page($list_xml);
        make_google_kml($list_xml);
    }

    $index_html = <<EOT;
<ul>
$index_html
</ul>
EOT

    Scramble::Misc::create("li/index.html", 
                           Scramble::Misc::make_1_column_page(title => "Peak Lists",
                                                              html => $index_html,
                                                              'include-header' => 1));
}

1;
