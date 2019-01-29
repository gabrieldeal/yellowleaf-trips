package Scramble::Controller::ListPage;

use strict;

use Scramble::Controller::ElevationFragment ();
use Scramble::Controller::MapFragment ();
use Scramble::Model::List ();
use Scramble::Misc ();

sub new {
    my ($arg0, $list) = @_;

    my $self = {
        list => $list,
    };
    bless($self, ref($arg0) || $arg0);

    $self->{locations} = $self->initialize_locations;

    return $self;
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

    my @rows;
    foreach my $list_location ($list->get_locations) {
        my @cells = map { { value_html => get_cell_value($_, $list_location) } } $list->get_columns;
        push @rows, { cells => \@cells }
    }

    my @images = $self->get_images_to_display('max-images' => 100);
    my @image_params = map {
        Scramble::Controller::ImageFragment->new($_)->params;
    } @images;

    my $params = {
        images => \@image_params,
        list_columns => \@columns,
        list_rows => \@rows,
        map_inputs => $self->get_map_params,
    };
    my $html = Scramble::Template::html('list/page', $params);

    Scramble::Misc::create($list->get_list_path,
                           Scramble::Template::page_html(title => $list->get_name,
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

sub get_images_to_display {
    my $self = shift;
    my (%args) = @_;

    my $max_images = $args{'max-images'};
    my $locations = $self->{locations};

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

sub get_map_params {
    my $self = shift;

    my $options = {
        'kml-url' => $self->{list}->get_kml_url,
    };

    return [Scramble::Controller::MapFragment::params($self->{locations}, $options)];
}

sub initialize_locations {
    my $self = shift;

    my @locations;
    foreach my $list_location ($self->{list}->get_locations) {
        my $location_object = $list_location->get_location_object;
	if ($location_object) {
	    push @locations, $location_object;
	}
    }

    return \@locations;
}

1;
