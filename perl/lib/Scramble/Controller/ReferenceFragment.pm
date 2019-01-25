package Scramble::Controller::ReferenceFragment;

use strict;

# FIXME: Refactor this.

sub get_reference_html {
    my ($reference) = @_;

    my $retval = eval { get_reference_html_with_name_only($reference) };
    if (! defined $retval) {
        die "Can not find " . Data::Dumper::Dumper($reference);
    }

    my $type = get_type($reference);

    my $note = $reference->get_note() || '';
    if ($note) {
        $note = Scramble::Misc::insert_links($note);
        $note = " ($note)";
    }

    return "$type: $retval$note";
}

sub get_type {
    my ($reference) = @_;

    my $type = $reference->get_type()
        or Carp::confess("missing type for " . Data::Dumper::Dumper($reference));
    if ($reference->get_season()) {
        $type = ucfirst($reference->get_season()) . " $type";
    }

    return $type;
}

sub get_page_reference_html {
    my ($reference) = @_;

    my $type = $reference->get_type();
    if (defined $type && $type =~ /book/i) {
        return get_reference_html($reference);
    }

    my $name = $reference->get_name() || die "No name in " . Data::Dumper::Dumper($reference);

    my $note = Scramble::Misc::make_optional_line(" (%s)", $reference->get_note());
    return "$name: " .  get_reference_html_with_name_only($reference) . $note;
}

sub get_reference_html_with_name_only {
    my ($reference, %options) = @_;

    my $retval = '';
    my $id = $reference->get_id();
    my $url = $reference->get_url();
    my $name = $reference->get_page_name() || $reference->get_name();
    defined $name or Carp::confess("Unable to get name from " . Data::Dumper::Dumper($reference));

    my $type = $reference->get_type();

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
    foreach my $reference (sort { Scramble::Model::Reference::cmp($b, $a) } @references) {
	my $reference_html = get_page_reference_html($reference);
	next if $eliminate_duplicates{$reference_html};
	$eliminate_duplicates{$reference_html} = 1;
	push @retval, $reference_html;
    }

    return @retval;
}

1;
