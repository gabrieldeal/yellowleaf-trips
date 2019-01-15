package Scramble::Model::Reference;

use strict;

use Scramble::Model;

my $g_collection = Scramble::Collection->new();

sub get_all { $g_collection->get_all() }
sub find_or_create {
    my ($reference_xml) = @_;

    if ($reference_xml->{id}) {
        return $g_collection->find_one(id => $reference_xml->{id});
    }

    return Scramble::Model::Reference->new($reference_xml);
}

sub new {
    my ($arg0, $data) = @_;

    my $self = { %$data };

    if(grep { !/^(id|name|skip|page-name|note|season|link|type|URL)$/ } keys %$data) {
        die "Unrecognized attribute in " . Data::Dumper::Dumper($data);
    }

    return bless($self, ref($arg0) || $arg0);
}

sub open {
    my ($data_dir) = @_;

    my $file = "$data_dir/references.xml";
    my $references_xml = Scramble::Model::parse($file);

    foreach my $reference_xml (@{ $references_xml->{reference} }) {
        my $reference = Scramble::Model::Reference->new($reference_xml);
        $g_collection->add($reference);
    }
}

sub get_id { $_[0]->{id} }
sub get_name { $_[0]->{name} || $_[0]->{'page-name'} }
sub get_page_name { $_[0]->{'page-name'} }
sub get_note { $_[0]->{note} }
sub get_season { $_[0]->{season} }
sub should_link { $_[0]->{link} }
sub should_skip { $_[0]->{skip} }
sub get_type { $_[0]->{type} }
sub get_url { $_[0]->{URL} }

sub get_cmp_value {
    my ($self) = @_;

    my $cmp_value = $self->get_type();
    if (defined $cmp_value) {
	$cmp_value = lc($cmp_value);
    }
    if (! defined $cmp_value && defined $self->get_page_name()) {
	$cmp_value = "webpage";
    }
    my $season = $self->get_season();
    if (defined $season) {
        $cmp_value = "$season $cmp_value";
    }

    if (! defined $self->get_id()) {
	die "unable to determine type: " . Data::Dumper::Dumper($self)
	    unless defined $cmp_value;
	return $cmp_value;
    }elsif ('routeMap' eq $self->get_id()) {
	return "1";
    } elsif ('topozoneMap' eq $self->get_id()) {
	return "2";
    } else {
	die "unable to determine type: " . Data::Dumper::Dumper($self)
	    unless defined $cmp_value;
	return $cmp_value;
    }
}
sub cmp {
    my ($a, $b) = @_;

    my $a_cmp_value = get_cmp_value($a);
    my $b_cmp_value = get_cmp_value($b);

    my $astring = $a_cmp_value . hu($a->get_name());
    my $bstring = $b_cmp_value . hu($b->get_name());
    return $astring cmp $bstring;
}

sub hu { $_[0] ? $_[0] : '' }

1;
