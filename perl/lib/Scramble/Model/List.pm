package Scramble::Model::List;

use strict;

use Scramble::Misc;
use Scramble::Model;
use Scramble::Model::List::Location;
use Scramble::Logger;

my $g_collection = Scramble::Collection->new;

sub get_all {
    return $g_collection->get_all();
}

sub new {
    my ($arg0, $list_xml) = @_;

    my @unrecognized_attributes = grep { !/^(name|path|sortby|id|content|columns|location|quad)$/ } keys %$list_xml;
    if(@unrecognized_attributes) {
        local $Data::Dumper::Maxdepth = 1;
        die "Unrecognized attribute (@unrecognized_attributes) in " . Data::Dumper::Dumper($list_xml);
    }

    my @columns = ($list_xml->{columns}
                   ? split(/,\s*/, $list_xml->{columns})
                   : qw(order name elevation quad));

    my $self = {
        columns => \@columns,
        content => $list_xml->{content},
        id => $list_xml->{id},
        name => $list_xml->{name},
        quad => $list_xml->{quad},
        sortby => $list_xml->{sortby},
    };
    bless($self, ref($arg0) || $arg0);

    $self->_initialize_list_locations($list_xml->{location});

    return $self;
}

sub get_columns { @{ $_[0]->{columns} } }
sub get_content { $_[0]->{content} }
sub get_id { $_[0]->{id} }
sub get_locations { @{ $_[0]->{list_locations} } }
sub get_name { $_[0]->{name} }
sub get_quad { $_[0]->{quad} }
sub get_sortby { $_[0]->{sortby} }
sub should_skip { $_[0]->{skip} }

sub get_url {
    my $self = shift;

    return sprintf("../%s", $self->get_list_path());
}

sub _list_location_equals {
    my ($a, $b) = @_;

    return ($a->{'name'} eq $b->{'name'}
            && $a->{'quad'} eq $b->{'quad'}
            && (! $a->{'county'}
                || $a->{'county'} eq $b->{'county'}));
}

sub _initialize_list_locations {
    my $self = shift;
    my ($list_location_xmls) = @_;

    my @list_locations = map { Scramble::Model::List::Location->new($_) } @$list_location_xmls;
    @list_locations = sort { $self->_cmp_list_locations($a, $b) } @list_locations;

    # Now that it is sorted, find duplicate locations:
    for (my $i = 0; $i + 1 < @list_locations; ++$i) {
        my $cur = $list_locations[$i];
        my $next = $list_locations[$i+1];
        if (_list_location_equals($cur, $next)) {
            local $Data::Dumper::Maxdepth = 2;
            die("Duplicate list locations:"
                . Data::Dumper::Dumper($cur) . "\n"
                . Data::Dumper::Dumper($next) . "\n");

        }
    }

    my $count = 1;
    map { $_->set_order($count++) } @list_locations;

    $self->{list_locations} = \@list_locations;
}

sub open {
    my (@paths) = @_;
    
    my @list_xmls = Scramble::Model::open_documents(@paths);
    @list_xmls or die "No lists";

    foreach my $list_xml (@list_xmls) {
        Scramble::Logger::verbose "Reading list $list_xml->{path}\n";
        my $list = Scramble::Model::List->new($list_xml);
        $g_collection->add($list);
    }
}

sub _cmp_list_locations {
    my $self = shift;
    my ($list_location1, $list_location2) = @_;

    if ($self->get_sortby eq 'elevation') {
        my %e1 = Scramble::Misc::get_elevation_details($list_location1->get_elevation);
        my %e2 = Scramble::Misc::get_elevation_details($list_location2->get_elevation);
	return $e2{feet} <=> $e1{feet};
    } elsif ($self->get_sortby eq 'MVD') {
        return $list_location2->get_mvd <=> $list_location1->get_mvd;
    } elsif ($self->get_sortby eq 'order') {
        return $list_location2->get_order <=> $list_location1->get_order;
    } else {
        die "Not implemented: " . $self->get_sortby;
    }
}


sub get_list_path {
    my $self = shift;

    my $name = $self->get_id;

    # For preserving the odd, legacy paths:
    $name =~ s/-/--/g;
    if ($self->get_sortby ne 'order') {
        $name .= $self->get_sortby;
    }

    return "li/$name.html";
}

sub get_link_html {
    my ($self) = @_;

    return sprintf(qq(<a href="%s">%s</a>),
                   $self->get_url,
                   $self->get_name);
}

sub get_kml_path {
    my ($self) = @_;

    my $kml_path = $self->get_list_path;
    $kml_path =~ s/\.html/.kml/;

    return $kml_path;
}

sub get_kml_url {
    my ($self) = @_;

    my $path = $self->get_kml_path;

    return "../$path";
}

1;
