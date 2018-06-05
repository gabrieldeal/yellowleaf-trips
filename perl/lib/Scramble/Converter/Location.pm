package Scramble::Converter::Location;

use strict;

use XML::Generator ();

sub new {
    my ($arg0) = @_;

    my $self = {
	xml_generator => XML::Generator->new(escape => 'always',
					     conformance => 'strict',
					     pretty => 4)
    };

    return bless $self, ref($arg0) || $arg0;
}

sub get_xml_generator { $_[0]->{xml_generator} }
sub get_location { $_[0]->{location} }

sub convert {
    my $self = shift;
    my (@locations) = @_;

    my @xmls = map { $self->convert_one($_) } @locations;
    
    return $self->get_xml_generator()->locations({}, @xmls);
}

sub convert_one {
    my $self = shift;
    my ($location) = @_;

    $self->{location} = $location;
    my $xg = $self->get_xml_generator();

    my @tags;
    push @tags, $self->make_name_tag();
    push @tags, $self->make_coordinates_tag();
    push @tags, $self->make_areas_tag();
    push @tags, $self->make_named_array_tag('maps', 'map');
    push @tags, $self->make_named_array_tag('references', 'reference');
    push @tags, $xg->description($location->get_description());

    return $xg->location($self->make_location_attributes(), @tags);
}

sub make_coordinates_tag {
    my $self = shift;

    my $l = $self->get_location();
    my $xg = $self->get_xml_generator() || die;

    return $xg->coordinates({ datum => $l->get_map_datum(),
			      latitude => $l->get_latitude(),
			      longitude => $l->get_longitude()
			  });
}

sub make_name_tag {
    my $self = shift;

    my $l = $self->get_location();
    my $xg = $self->get_xml_generator() || die;

    my $attributes = {
	value => $l->get_name(),
	'unofficial-name' => $l->get_is_unofficial_name()
    };

    my @tags;
    foreach my $aka ($l->get_aka_names()) {
	push @tags, $xg->AKA({ name => $aka });
    }
    if (defined $l->get_naming_origin()) {
	push @tags, $xg->origin($l->get_naming_origin());
    }

    return $xg->name($attributes, @tags);
}

sub make_location_attributes {
    my $self = shift;

    my $l = $self->get_location();
    return {
	type => $l->get_type(),
	elevation => $l->get_elevation(),
	prominence => $l->get_prominence(),
	id => $l->_get_optional('id'),
    };
}

sub make_named_array_tag {
    my $self = shift;
    my ($name, $sub_name) = @_;

    my $l = $self->get_location();
    my $xg = $self->get_xml_generator();

    my @tags;
    foreach my $tag (@{ $l->_get_optional($name, $sub_name) || [] }) {
	push @tags, $xg->$sub_name($tag);
    }

    return $xg->$name({}, @tags);
}

sub make_areas_tag {
    my $self = shift;

    my $l = $self->get_location();
    my $xg = $self->get_xml_generator();

    my @areas;
    foreach my $area ($l->get_areas_collection()->get_all()) {
	push @areas, $xg->area({ id => $area->get_id() });
    }

    return $xg->areas({}, @areas);
}


1;
