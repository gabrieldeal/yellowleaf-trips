package Scramble::Reference;

use strict;

use Scramble::XML;

my $g_references_xml;

sub open {
    my $file = "data/references.xml";
    $g_references_xml = Scramble::XML::parse($file,
					     "keyattr" => ["id"]);
    if ("HASH" ne ref($g_references_xml->{'reference'})) {
        die "$file is malformed.  Is there a missing 'id' attribute?";
    }
}

sub get_ids {
    return keys(%{ $g_references_xml->{'reference'} });
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
sub make_references {
    my $references_html;
    my @references = values %{ $g_references_xml->{'reference'} };
    foreach my $reference (sort { cmp_references($a, $b) } @references) {
	next unless $reference->{'name'};
	next unless $reference->{'link'};
	$references_html .= sprintf("<li>%s</li>", get_reference_html($reference));
    }

    Scramble::Misc::create("m/references.html",
			   Scramble::Misc::make_2_column_page("Links",
							      qq(<ul>$references_html</ul>)));
}

sub get_map_htmls {
    my ($maps) = @_;
    @_ == 1 or die "old-style arguments";

    my @maps;
    if (defined $maps) {
	push @maps, @$maps;
    }

#    die "No maps" unless @maps;

    my @retval;
    my %remove_duplicates;
    foreach my $map (@maps) {
	my $dedup_key = hu($map->{'id'}) . "|" . hu($map->{'name'}) . "|" . hu($map->{'URL'});;
	next if exists $remove_duplicates{$dedup_key};
	$remove_duplicates{$dedup_key} = 1;

	push @retval, get_reference_html($map);
    }

    return @retval;
}

sub get_reference_for_id {
    my ($id) = @_;

    return ($g_references_xml->{'reference'}{$id}
	    || die "Unable to find reference for ID '$id'");
}

sub get_map_type { $_[0]->{'id'} }
sub get_map_name { $_[0]->{'name'} }

sub get_reference_html {
    my ($reference) = @_;

    my $retval = eval { get_reference_html_with_name_only($reference) };
    if (! defined $retval) {
	my $error = $@;
	if ('USGS quad' ne get_reference_attr('type', $reference)) {
	    die $error;
	} elsif(! defined($retval = get_reference_attr('name', $reference))) {
            die "no name for " . Data::Dumper::Dumper($reference);
	}
    }

    my $type = get_reference_attr('type', $reference)
        or Carp::confess "missing type for " . Data::Dumper::Dumper($reference);
    my $season = get_reference_attr('season', $reference);
    if ($season) {
        $type = ucfirst($season) . " $type";
    }

    my $note = Scramble::Misc::insert_links(get_reference_attr('note', $reference) || '');
    if ($note) {
	$note = " ($note)";
    }

    return "$type: $retval$note";
}

sub get_page_reference_html {
    my ($reference) = @_;

    my $type = get_reference_attr('type', $reference);
    if (defined $type && $type =~ /book/i) {
	return get_reference_html($reference);
    }

    my $name = get_reference_attr('name', $reference)
	|| die "No name in " . Data::Dumper::Dumper($reference);
	
    my $note = Scramble::Misc::make_optional_line(" (%s)",
						  get_reference_attr('note', $reference));
    return "$name: " .  get_reference_html_with_name_only($reference, 'name-ids' => ["page-name", "type"]) . $note;
}

sub get_reference_html_with_name_only {
    my ($reference, %options) = @_;

    my $retval = '';
    my $id = $reference->{'id'};
    my $url = get_reference_attr('URL', $reference);

    my @name_ids = qw(name);
    if (defined $options{'name-ids'}) {
	@name_ids = @{ $options{'name-ids'} };
    }
    my $name;
    foreach my $id (@name_ids) {
	$name = get_reference_attr($id, $reference);
	last if defined $name;
    }

    defined $name or Carp::confess "Unable to get name from " . Data::Dumper::Dumper($reference);

    my $type = get_reference_attr('type', $reference);

    if ($url) {
        if ($id && $id eq 'USGS quad') {
	    $retval .= Scramble::Misc::make_usgs_quad_link($name);
	} else {
	    $retval .= qq(<a href="$url">$name</a>);
	}
    } elsif (defined $type && $type =~ /book/i) {
	$retval .= "<u>$name</u>";
    } else {
        $retval .= "$name";
    }

    return $retval;
}

# References to a page within a site (probably a trip report) instead
# of the home page for the site.  Used on the "trip reports and
# references" section.
sub get_page_references_html {
    my (@references) = @_;

    my @retval;
    my %eliminate_duplicates;
    foreach my $reference (sort { cmp_references($b, $a) } @references) {
	my $reference_html = get_page_reference_html($reference);
	next if $eliminate_duplicates{$reference_html};
	$eliminate_duplicates{$reference_html} = 1;
	push @retval, $reference_html;
    }

    return @retval;
}

sub get_reference_attr {
    my ($attr, $reference) = @_;

    if ($reference->{$attr}) {
	return $reference->{$attr};
    }

    if (! $reference->{'id'}) {
	return undef;
    }

    my $reference = $g_references_xml->{'reference'}{ $reference->{'id'} };
    if (! defined $reference) {
	return undef;
    }

    return $reference->{$attr};
}

1;
