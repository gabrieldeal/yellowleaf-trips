package Scramble::Model;

use strict;

use XML::Simple ();
use Scramble::Logger;
use List::Util ();

sub _get_optional_content {
    my $self = shift;
    my ($name) = @_;

    return undef unless exists $self->{$name};
    return $self->{$name}[0] if ref $self->{$name} eq 'ARRAY';
    return undef if ref $self->{$name} eq 'HASH' && 0 == keys(%{ $self->{$name} });
    die Data::Dumper::Dumper($self->{$name}) if ref $self->{$name};
    return $self->{$name} if defined $self->{$name} && length($self->{$name});
    return undef;
}

sub _set_required {
  my $self = shift;

  $self->_set(1, @_);
}
sub _set_optional {
  my $self = shift;

  $self->_set(0, @_);
}

sub _set {
  my $self = shift;
  my ($is_required, @attrs) = @_;

  foreach my $attr (@attrs) {
    my $value = $self->_get_optional($attr);
    die "Missing required attribute '$attr': " . Data::Dumper::Dumper($self) if ! $value && $is_required;
    $self->{$attr} = $value;
  }
}

sub _get_required {
    my $self = shift;
    my (@keys) = @_;

    return $self->_get_optional(@keys) || die "Missing @keys: " . Data::Dumper::Dumper($self);
}
sub _get_optional {
    my $self = shift;
    my (@keys) = @_;

    my $hr = $self;
    foreach my $key (@keys) {
	return undef unless UNIVERSAL::isa($hr, 'HASH');
	return undef unless exists $hr->{$key};
	$hr = $hr->{$key};
    }

    return $hr;
}

sub set {
    my $self = shift;
    my ($key, $value) = @_;

    if (! ref $key) {
	$self->{$key} = $value;
    } elsif (@$key == 2) { # how to do generically?
	$self->{$key->[0]}{$key->[1]} = $value;
    } else {
	die "Not supported: " . Data::Dumper::Dumper($key);
    }
}

######################################################################
# shared between Scramble::Model::Location and Scramble::Model::Report
######################################################################

sub get_areas_from_xml {
    my $self = shift;

    my $areas_xml = $self->_get_optional('areas');
    return unless $areas_xml;

    my @areas;
    foreach my $area_tag (@{ $areas_xml->{'area'} }) {
	push @areas, Scramble::Model::Area::get_all()->find_one('id' => $area_tag->{'id'})
    }

    return @areas;
}

sub get_recognizable_areas_html {
    my $self = shift;
    my (%args) = @_;

    return '' if defined $self->_get_optional('areas') && ! @{ $self->_get_optional('areas', 'area') };

    my @areas = $self->get_areas_collection()->find('is-recognizable-area' => 'true');
    return '' unless @areas;

    return Scramble::Misc::make_colon_line("In", join(", ", map { $_->get_short_name() } @areas));
}

######################################################################
# static methods
######################################################################

sub open_documents {
    my (@paths) = @_;

    my @xmls;
    foreach my $path (@paths) {
	my $xml = parse($path);
	if ($xml->{'skip'}) {
	    Scramble::Logger::verbose "Skipping $path\n";
	    next;
	}

	push @xmls, $xml;
    }

    return @xmls;
}


sub parse {
    my ($path, %options) = @_;
    
    if (0 == scalar keys %options) {
	%options = ("forcearray" => [
				     'AKA',
				     'area',
                                     'attempted',
				     'comments', 
				     'directions',
				     'file',
				     'location', 
				     'map', 
                                     'member',
                                     'not',
                                     'party',
				     'picture',
				     'reference',
				     'route', 
                                     'rock-route',
				     'distance',
                                     'image',
				     ],
		    "keyattr" => []);
    }
    Scramble::Logger::verbose "Parsing $path\n";
    my $xs = XML::Simple->new();
    my $xml = eval { $xs->XMLin($path, %options) };
    if ($@) {
        die "Error parsing '$path': $@";
    }

    $xml->{'path'} = $path;

    return $xml;
}

1;
