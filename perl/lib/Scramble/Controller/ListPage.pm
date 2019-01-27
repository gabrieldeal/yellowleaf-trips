package Scramble::Controller::ListPage;

use strict;

use Scramble::Controller::ElevationFragment ();
use Scramble::Controller::MapFragment ();
use Scramble::Model::List ();
use Scramble::Misc ();

# FIXME: Refactor display code into a template.

sub new {
    my ($arg0, $list) = @_;

    my $self = {
        list => $list,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create_all {
    foreach my $list (Scramble::Model::List::get_all()) {
        if ($list->should_skip) {
            next;
        }

        Scramble::Logger::verbose("Making list page for " . $list->get_name . "\n");
        my $page = Scramble::Controller::ListPage->new($list);
        $page->create();
    }
}

sub create {
    my $self = shift;

    my $list = $self->{list};

    my @columns;
    foreach my $column_name ($list->get_columns) {
        push @columns, {
            name => get_cell_title($column_name),
        };
    }

    my @location_objects;
    my @rows;
    foreach my $list_location ($list->get_locations) {
        my $location_object = $list_location->get_location_object;
	if ($location_object) {
	    push @location_objects, $location_object;
	}

        my @cells = map { { value_html => get_cell_value($_, $list_location) } } $list->get_columns;
        push @rows, { cells => \@cells }
    }

    my $template = Scramble::Template::create('list/page');
    $template->param(columns => \@columns,
                     rows => \@rows);
    my $locations_html = $template->output();

    my $max_images = 100;

    my @images = get_images_to_display_for_locations('locations' => \@location_objects,
						     'max-images' => $max_images);
    my @htmls = [$locations_html];
    push @htmls, get_map_html($list, \@location_objects) if @location_objects;

    my $images_html = Scramble::Controller::ImageListFragment::html(htmls => [$locations_html],
                                                                    images => \@images,
                                                                    'float-first' => 1);

    my $title = $list->get_name;

    my $html = <<EOT;
$images_html
<br clear="all" />
EOT

    Scramble::Misc::create($list->get_list_path,
                           Scramble::Template::page_html(title => $title,
                                                         html => $html,
                                                         'enable-embedded-google-map' => 1,
                                                         'include-header' => 1));
}

sub get_cell_value {
    my ($name, $list_location) = @_;

    if ($name eq 'name') {
        return (get_location_link_html('name' => $list_location->{'name'},
				       'quad' => $list_location->{'quad'})
                . ($list_location->get_is_unofficial_name ? "*" : '')
		. Scramble::Misc::make_optional_line(" (AKA %s)",
                                                     $list_location->get_aka_names));
    } elsif ($name eq 'elevation') {
        return Scramble::Controller::ElevationFragment::format_elevation_short($list_location->get_elevation);
    } elsif ($name eq 'quad') {
        return '' unless $list_location->{'quad'};
        my $quad = eval { Scramble::Model::Area::get_all()->find_one('id' => $list_location->{'quad'},
                                                                     'type' => 'USGS quad') };
        return $list_location->{'quad'} unless $quad;
        return $quad->get_short_name();
    } elsif ($name eq 'description') {
        return Scramble::Htmlify::insert_links($list_location->{$name});
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
    my ($list, $locations) = @_;

    my %options = ('kml-url' => $list->get_kml_url);
    Scramble::Controller::MapFragment::html($locations, \%options);
}

1;
