package Scramble::Controller::ListPage;

use strict;

use Scramble::Controller::ElevationFragment qw(format_elevation_short);
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

sub create_all {
    my ($writer) = @_;

    foreach my $list (Scramble::Model::List::get_all()) {
        if ($list->should_skip) {
            next;
        }

        Scramble::Logger::verbose("Making list page for " . $list->get_name . "\n");
        my $page = Scramble::Controller::ListPage->new($list);
        $page->create($writer);
    }
}

sub create {
    my $self = shift;
    my ($writer) = @_;

    my $list = $self->{list};

    my @columns;
    foreach my $column_name ($list->get_columns) {
        push @columns, {
            name => get_cell_title($column_name),
        };
    }

    my @rows;
    foreach my $list_location ($list->get_locations) {
        my @cells = map { get_cell_params($_, $list_location) } $list->get_columns;
        push @rows, { cells => \@cells }
    }

    my @pictures = $self->get_pictures_to_display('max-pictures' => 100);
    my @picture_params = map {
        Scramble::Controller::PictureFragment->new($_)->params;
    } @pictures;

    my $params = {
        pictures => \@picture_params,
        list_columns => \@columns,
        list_rows => \@rows,
        map_inputs => $self->get_map_params,
    };
    my $html = Scramble::Template::html('list/page', $params);

    $writer->create($list->get_list_path,
                    Scramble::Template::page_html(title => $list->get_name,
                                                  html => $html,
                                                  'enable-embedded-google-map' => 1,
                                                  'include-header' => 1));
}

sub get_cell_params {
    my ($name, $list_location) = @_;

    if ($name eq 'name') {
        return get_location_name_cell_params(name => $list_location->get_name,
                                             quad => $list_location->get_quad);
    }

    my $value;
    if ($name eq 'elevation') {
        $value = format_elevation_short($list_location->get_elevation);
    } elsif ($name eq 'quad') {
        $value = get_quad_cell_params($list_location);
    } elsif ($name eq 'order') {
        $value = $list_location->get_order;
    } elsif ($name eq 'note') {
        $value = $list_location->get_note;
    } elsif ($name eq 'county') {
        $value = $list_location->get_county;
    } else {
        die "Unrecognized field '$name'";
    }

    return {
        value_html => $value,
    };
}

sub get_quad_cell_params {
    my ($list_location) = @_;

    my $quad_id = $list_location->get_quad;
    return unless $quad_id;

    my $quad = eval {
        Scramble::Model::Area::get_all()->find_one('id' => $quad_id,
                                                   'type' => 'USGS quad')
    };
    return $quad->get_short_name if $quad;

    return $quad_id;
}

sub get_location_name_cell_params {
    my (%args) = @_;

    my $location = eval { Scramble::Model::Location::find_location(%args) };
    if ($location) {
        return {
            url => $location->get_url,
            value_html => $location->get_name,
        };
    }

    return {
        value_html => $args{'name'},
    };
}

my %gCellTitles = ('name' => 'Location Name',
		   'elevation' => 'Elevation',
		   'quad' => 'USGS quad',
		   'description' => 'name',
		   );
sub get_cell_title { return $gCellTitles{$_[0]} || ucfirst($_[0]) }

sub get_pictures_to_display {
    my $self = shift;
    my (%args) = @_;

    my $max_pictures = $args{'max-pictures'};
    my $locations = $self->{locations};

    my @pictures;
    foreach my $location (@$locations) {
      my @location_pictures = $location->get_picture_objects();
      @location_pictures = sort { $a->cmp($b) } @location_pictures;
      push @pictures, $location_pictures[0] if @location_pictures;
    }

    @pictures = Scramble::Misc::dedup(@pictures);
    @pictures = sort { $a->cmp($b) } @pictures;
    if (@pictures > $max_pictures) {
	@pictures = @pictures[0..$max_pictures-1];
    }

    return @pictures;
}

sub get_map_params {
    my $self = shift;

    my $options = {
        'kml-url' => $self->{list}->get_kml_url,
    };

    return [Scramble::Controller::MapFragment::params($self->{locations}, $options)];
}

1;
