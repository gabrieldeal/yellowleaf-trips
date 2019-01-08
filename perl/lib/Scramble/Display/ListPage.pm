package Scramble::Display::ListPage;

use strict;

use Scramble::Model::List ();
use Scramble::Misc ();

# FIXME: Refactor display code into a template.

sub new {
    my ($arg0, $list_xml) = @_;

    my $self = {
        list_xml => $list_xml,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create_all {
    foreach my $list_xml (Scramble::Model::List::get_all_lists()) {
        if ($list_xml->{'skip'}) {
            next;
        }

        Scramble::Logger::verbose("Making list page for $list_xml->{name}\n");
        my $page = Scramble::Display::ListPage->new($list_xml);
        $page->create();
    }
}

sub create {
    my $self = shift;

    my $list_xml = $self->{list_xml};

    my @location_objects;
    my $county = $list_xml->{'location'}[0]{'county'};

    my @column_names = qw(order name elevation quad);
    if ($list_xml->{'columns'}) {
	@column_names = split(/,\s*/, $list_xml->{'columns'});
    }

    my @columns;
    foreach my $column_name (@column_names) {
        push @columns, {
            name => get_cell_title($column_name),
        };
    }

    my @rows;
    foreach my $list_location (@{ $list_xml->{'location'} }) {
        my $location_object = Scramble::Model::List::get_location_object($list_location);
	if ($location_object) {
	    push @location_objects, $location_object;
	}

        push @rows, {
            cells => [ map { { value_html => get_cell_value($_, $list_location) } } @column_names ],
        }
    }

    my $template = Scramble::Template::create('list/table');
    $template->param(columns => \@columns,
                     rows => \@rows);
    my $locations_html = $template->output();

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
    my @image_fragments = map { Scramble::Display::ImageFragment->new($_) } @images;
    my @image_htmls = map { Scramble::Misc::make_cell_html(content => $_->create()) } @image_fragments;

    my @cells = ($locations_html);
    push @cells, get_map_html($list_xml, \@location_objects) if @location_objects;
    push @cells, @image_htmls;

    my $images_html = Scramble::Misc::render_cells_into_flow(\@cells, 'float-first' => 1);

    my $title = $list_xml->{'name'};

    my $html = <<EOT;
$note
$images_html
EOT

    Scramble::Misc::create(Scramble::Model::List::get_list_path($list_xml),
			   Scramble::Misc::make_1_column_page(title => $title,
							      html => $html,
                                                              'enable-embedded-google-map' => 1,
                                                              'include-header' => 1));
}

sub get_cell_value {
    my ($name, $list_location) = @_;

    if ($name eq 'name') {
        return (get_location_link_html('name' => $list_location->{'name'},
				       'quad' => $list_location->{'quad'})
                . (Scramble::Model::List::get_is_unofficial_name($list_location) ? "*" : '')
		. Scramble::Misc::make_optional_line(" (AKA %s)",
                                                     Scramble::Model::List::get_aka_names($list_location)));
    } elsif ($name eq 'elevation') {
        return Scramble::Misc::format_elevation_short(Scramble::Model::List::get_elevation($list_location));
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

sub get_location_link_html {
    my (%args) = @_;

    return eval {
	my $location = Scramble::Model::Location::find_location(%args);
	return $location->get_short_link_html();
    } || $args{'name'};
}

sub get_map_html {
    my ($list_xml, $locations) = @_;

    my %options = ('kml-url' => Scramble::Model::List::get_kml_url($list_xml));
    Scramble::Misc::get_multi_point_embedded_google_map_html($locations, \%options);
}

1;
