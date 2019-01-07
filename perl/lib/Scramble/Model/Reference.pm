package Scramble::Model::Reference;

use strict;

use Scramble::Model;

# FIXME: Convert to a class.

my $g_references_xml;

sub open {
    my ($data_dir) = @_;

    my $file = "$data_dir/references.xml";
    $g_references_xml = Scramble::Model::parse($file, "keyattr" => ["id"]);
    if ("HASH" ne ref($g_references_xml->{'reference'})) {
        die "$file is malformed.  Is there a missing 'id' attribute?";
    }
}

sub get_all { $g_references_xml->{reference} }

sub get_ids {
    return keys(%{ get_all() });
}

sub get_type_for_cmp {
    my ($reference) = @_;

    my $type = get_reference_attr('type', $reference);
    if (defined $type) {
	$type = lc($type);
    }
    my $page_name = get_reference_attr('page-name', $reference);
    if (! defined $type && defined $page_name) {
	$type = "webpage";
    }
    my $season = get_reference_attr('season', $reference);
    if (defined $season) {
        $type = "$season $type";
    }

    my $id = get_reference_attr('id', $reference);
    if (! defined $id) {
	die "unable to determine type: " . Data::Dumper::Dumper($reference)
	    unless defined $type;
	return $type;
    }elsif ('routeMap' eq $id) {
	return "1";
    } elsif ('topozoneMap' eq $id) {
	return "2";
    } else {
	die "unable to determine type: " . Data::Dumper::Dumper($reference)
	    unless defined $type;
	return $type;
    }
}
sub cmp_references {
    my ($a, $b) = @_;

    my $atype = get_type_for_cmp($a);
    my $btype = get_type_for_cmp($b);

    my $astring = $atype . hu(get_reference_attr('name', $a));
    my $bstring = $btype . hu(get_reference_attr('name', $b));
    return $astring cmp $bstring;
}

sub hu { $_[0] ? $_[0] : '' }

sub get_map_type { $_[0]->{'id'} }
sub get_map_name { $_[0]->{'name'} }

sub get_reference_attr {
    my ($attr, $reference) = @_;

    if ($reference->{$attr}) {
	return $reference->{$attr};
    }

    if (! $reference->{'id'}) {
	return undef;
    }

    my $reference_xml = get_all()->{ $reference->{'id'} };
    if (! defined $reference_xml) {
	return undef;
    }

    return $reference_xml->{$attr};
}

1;
