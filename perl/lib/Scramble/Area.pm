package Scramble::Area;

use strict;

use Scramble::XML ();
use Scramble::Collection ();
use Scramble::Area::Quad ();

our @ISA = qw(Scramble::XML);

my $g_all;

sub new {
    my $arg0 = shift;
    my ($xml) = @_;

    my $self = { %$xml,
		 'locations' => {},
	     };
    bless($self, ref($arg0) || $arg0);

    $self->_set_required(qw(type id name));
    $self->_set_optional(qw(weather-id URL));

    if ($self->get_type() eq 'USGS quad') {
      $self = Scramble::Area::Quad->new($self);
    }


    return $self;
}

sub get_name { $_[0]->{name} }
sub get_short_name { $_[0]->get_name() }
sub get_id { $_[0]->{id} }
sub get_type { $_[0]->{type} }
sub get_is_recognizable_area { $_[0]->_get_optional('is-recognizable-area') ? 'true' : 0 }
sub get_info_url { $_[0]->{URL} }

sub in_areas_transitive_closure {
    my $self = shift;

    my @areas;
    foreach my $area ($self->get_in_areas_collection()->get_all()) {
        push @areas, $area;
        push @areas, $area->in_areas_transitive_closure();
    }

    return @areas;
}

sub equals {
    my $self = shift;
    my ($obj) = @_;

    if (ref $obj) {
      return $self->get_id() eq $obj->get_id();
    } else {
      return $self->get_id() eq $obj;
    }
}

sub get_in_areas_collection {
    my $self = shift;

    if (! $self->{'in-areas-object'}) {
	# Need to do this lazily because it needs to happen after all area objects have been opened.
	my @areas = map { Scramble::Area::get_all()->find_one('id' => $_) } $self->in_area_ids();
	$self->{'in-areas-object'} = Scramble::Collection->new('objects' => \@areas);
	$self->{'in-areas-object'}->add($self->in_areas_transitive_closure());
    }
    return $self->{'in-areas-object'};
}
sub in_area_objects { $_[0]->get_in_areas_collection()->get_all() }
sub in_area_ids {
    my $self = shift;

    my $ids = $self->_get_optional('in-areas');
    return () unless $ids;
    return split(/,\s*/, $ids);
}

sub get_locations { values %{ $_[0]->{'locations'} } }
sub add_location {
    my $self = shift;
    my ($location) = @_;

    $self->{'locations'}{$location->get_id()} = $location;
}

######################################################################
# statics
######################################################################

sub get_all { $g_all }

sub open {
    my ($data_dir) = @_;

    return if $g_all;

    my @areas;
    my $areas_xml = Scramble::XML::parse("$data_dir/areas.xml");
    foreach my $area_xml (@{ $areas_xml->{'area'} }) {
	my $area = Scramble::Area->new($area_xml);
	push @areas, $area;
    }

    $g_all = Scramble::Collection->new('objects' => \@areas);

    foreach my $quad ($g_all->find('type' => 'USGS quad')) {
	foreach my $dirs (['north', 'south'], ['south', 'north'], ['east', 'west'], ['west', 'east']) {
	    my $neighbor_id = $quad->get_neighboring_quad_id($dirs->[0]);
	    next unless $neighbor_id;

	    my $neighbor = eval { Scramble::Area::get_all()->find_one('id' => $neighbor_id) };
	    if (! $neighbor) {
		$neighbor = Scramble::Area->new({ 'id' => $neighbor_id,
						  name => $neighbor_id,
						  $dirs->[1] => $quad->get_id(),
						  'type' => $quad->get_type(),
						});
		get_all()->add($neighbor);
	    }
	    $neighbor->add_neighboring_quad_id($dirs->[1], $quad->get_id());
	}
    }
}

######################################################################

1;
