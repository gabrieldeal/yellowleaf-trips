package Scramble::XML;

use strict;

use XML::Simple ();
use Scramble::Logger;
use List::Util ();

sub new {
    my $arg0 = shift;
    my ($parsed_xml) = @_;

    return bless { 'xml' => $parsed_xml }, ref($arg0) || $arg0;
}

sub _get_optional_content {
    my $self = shift;
    my ($name) = @_;

    return undef unless exists $self->{'xml'}{$name};
    return ref $self->{'xml'}{$name} eq 'ARRAY' ?  $self->{'xml'}{$name}[0] : $self->{'xml'}{$name};
}

sub _get_required {
    my $self = shift;
    my (@keys) = @_;

    return $self->_get_optional(@keys) || die "Missing @keys: " . Data::Dumper::Dumper($self->{'xml'});
}
sub _get_optional {
    my $self = shift;
    my (@keys) = @_;

    my $hr = $self->{'xml'};
    foreach my $key (@keys) {
	return undef unless ref($hr) eq 'HASH';
	return undef unless exists $hr->{$key};
	$hr = $hr->{$key};
    }

    return $hr;
}

sub set {
    my $self = shift;
    my ($key, $value) = @_;

    if (! ref $key) {
	$self->{'xml'}{$key} = $value;
    } elsif (@$key == 2) { # how to do generically?
	$self->{'xml'}{$key->[0]}{$key->[1]} = $value;
    } else {
	die "Not supported: " . Data::Dumper::Dumper($key);
    }
}
sub should_not_warn { $_[0]->_get_optional('log-no-warnings') }
sub get_directory { $_[0]->{'xml'}{'directory'} }

######################################################################
# shared between Scramble::Location and Scramble::Report
######################################################################

sub has_pictures { scalar($_[0]->get_picture_objects()) }
sub get_map_objects { @{ $_[0]->{'map-objects'} } }
sub get_picture_objects { @{ $_[0]->{'picture-objects'} } }
sub set_picture_objects { $_[0]->{'picture-objects'} = $_[1] }
sub get_image_htmls {
    my $self = shift;
    my (%options) = @_;

    my $type = delete $options{'type'} || die "Missing type";

    my $method = "get_${type}_objects";
    return join("<p>", map { $_->get_html(%options) } $self->$method());
}
# sub get_2_column_image_htmls {
#     my $self = shift;
#     my (%options) = @_;

#     my $type = delete $options{'type'} || die "Missing type";

#     my $method = "get_${type}_objects";
#     my $count = 0;
#     my $col1 = '';
#     my $col2 = '';
#     foreach my $image ($self->$method()) {
#         my $html = sprintf("%s<p>", $image->get_html(%options));
#         if ($count++ % 2) {
#             $col2 .= $html;
#         } else {
#             $col1 .= $html;
#         }
#     }
#     return qq(<table><tr><td valign="top">$col1</td><td valign="top">$col2</td></tr></table>);
# }


# sub divide_into_columns {
#   my $self = shift;
#   my (%options) = @_;

#   my $htmls = $options{htmls};
#   my $n_columns = $options{'num-columns'};

#   my @columns;
#   my $column = 0;
#   foreach my $html (@$htmls) {
#     my $index = $column++ % $n_columns;
#     push @{ $columns[$index] }, $html;
#   }

#   return \@columns;
# }


# sub render_into_rows {
#     my $self = shift;
#     my ($columns) = @_;

#     my $html = '';
#     my $num_rows = List::Util::max(map { scalar(@$_) } @$columns);
#     foreach my $row (1 .. $num_rows) {
#       $html .= qq(<tr valign="top">);
#       foreach my $column (@$columns) {
# 	if ($row < @$column) {
# 	  $html .= sprintf("<td>%s</td>", $column->[$row-1]);
# 	} elsif ($row == @$column) {
# 	  $html .= sprintf(qq(<td rowspan="%d">%s</td>),
# 			    1 + $num_rows - $row,
# 			    $column->[$row-1]);
# 	}
#       }
#       $html .= "</tr>";
#     }

#     return $html;
# }

sub get_areas_from_xml {
    my $self = shift;

    my $areas_xml = $self->_get_optional('areas');
    return unless $areas_xml;

    my @areas;
    foreach my $area_tag (@{ $areas_xml->{'area'} }) {
	push @areas, Scramble::Area::get_all()->find_one('id' => $area_tag->{'id'})
    }

    return @areas;
}

sub get_recognizable_areas_html {
    my $self = shift;
    my (%args) = @_;

    my @areas = $self->get_areas_collection()->find('is-recognizable-area' => 'true');
    return '' unless @areas;

    return Scramble::Misc::make_colon_line(sprintf("In %s", Scramble::Misc::pluralize(scalar(@areas), "area")),
					   join(", ", map { $args{'no-link'} ? $_->get_short_name() : $_->get_short_link_html() } @areas));
}

sub get_driving_directions_html {
    my $self = shift;

    my $directions = $self->_get_optional('driving-directions', 'directions');
    if (! $directions) {
	my $d = $self->_get_optional_content('driving-directions');
	if ($d) {
	    die(sprintf("%s has old style driving-directions\n", $self->get_name()));
	}
	return undef;
    }

    my $html;
    foreach my $direction (@$directions) {
	if (! ref $direction) {
	    $html .= Scramble::Misc::htmlify($direction) . "<p>";
	} elsif (exists $direction->{'from-location'}) {
	    my $location = Scramble::Location::find_location('name' => $direction->{'from-location'},
							     'include-unvisited' => 1,
							     );
	    $html .= $location->get_driving_directions_html();
	} else {
	    die "Got bad direction: " . Data::Dumper::Dumper($direction);
	}
    }

    return $html;
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
				     'description',
				     'directions',
                                     'include-list',
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

    $xml->{'directory'} = $path;
    $xml->{'directory'} =~ s,/[^/]+$,,;

    my ($ofilename) = ($path =~ m,/([^/]+).xml$,);
    $ofilename .= ".html";
    $xml->{'filename'} = $ofilename;

    return $xml;
}

1;
