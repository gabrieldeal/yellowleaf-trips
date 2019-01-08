package Scramble::Display::ReferenceFragment;

use strict;

sub get_reference_html {
    my ($reference) = @_;

    my $retval = eval { get_reference_html_with_name_only($reference) };
    if (! defined $retval) {
        die "Can not find " . Data::Dumper::Dumper($reference);
    }

    my $type = Scramble::Model::Reference::get_reference_attr('type', $reference)
        or Carp::confess("missing type for " . Data::Dumper::Dumper($reference));
    my $season = Scramble::Model::Reference::get_reference_attr('season', $reference);
    if ($season) {
        $type = ucfirst($season) . " $type";
    }

    my $note = Scramble::Misc::insert_links(Scramble::Model::Reference::get_reference_attr('note', $reference) || '');
    if ($note) {
	$note = " ($note)";
    }

    return "$type: $retval$note";
}

sub get_page_reference_html {
    my ($reference) = @_;

    my $type = Scramble::Model::Reference::get_reference_attr('type', $reference);
    if (defined $type && $type =~ /book/i) {
        return get_reference_html($reference);
    }

    my $name = Scramble::Model::Reference::get_reference_attr('name', $reference)
	|| die "No name in " . Data::Dumper::Dumper($reference);

    my $note = Scramble::Misc::make_optional_line(" (%s)",
                                                  Scramble::Model::Reference::get_reference_attr('note', $reference));
    return "$name: " .  get_reference_html_with_name_only($reference, 'name-ids' => ["page-name", "type"]) . $note;
}

sub get_reference_html_with_name_only {
    my ($reference, %options) = @_;

    my $retval = '';
    my $id = $reference->{'id'};
    my $url = Scramble::Model::Reference::get_reference_attr('URL', $reference);

    my @name_ids = qw(name);
    if (defined $options{'name-ids'}) {
	@name_ids = @{ $options{'name-ids'} };
    }
    my $name;
    foreach my $id (@name_ids) {
        $name = Scramble::Model::Reference::get_reference_attr($id, $reference);
	last if defined $name;
    }

    defined $name or Carp::confess("Unable to get name from " . Data::Dumper::Dumper($reference));

    my $type = Scramble::Model::Reference::get_reference_attr('type', $reference);

    if ($url) {
        if ($id && $id eq 'USGS quad') {
            die "Is this dead code?"
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
    foreach my $reference (sort { Scramble::Model::Reference::cmp_references($b, $a) } @references) {
	my $reference_html = get_page_reference_html($reference);
	next if $eliminate_duplicates{$reference_html};
	$eliminate_duplicates{$reference_html} = 1;
	push @retval, $reference_html;
    }

    return @retval;
}

1;
