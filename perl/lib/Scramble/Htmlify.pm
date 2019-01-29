package Scramble::Htmlify;

use strict;

use Scramble::Controller::ReferenceFragment ();
use Scramble::Model::List ();
use Scramble::Model::Reference ();

=head1 Inserting links into text

The 'id' from references.xml turns into a link named by the 'name' for
the given 'id' to the 'URL' for the 'id'.

The 'id' from list names turns into a link with the 'name' from that list.

=cut
my %g_transformations;
sub make_link_transformations {
    foreach my $list (Scramble::Model::List::get_all()) {
        next unless $list->get_id;
        my $id = $list->get_id;

        my $link = $list->get_link_html;
	$g_transformations{'list'}{sprintf('\b%s\b', $id)} = _insert_links_pack($link);
    }

    foreach my $reference (Scramble::Model::Reference::get_all()) {
        my $reference_fragment = Scramble::Controller::ReferenceFragment->new($reference);
        my $html = Scramble::Template::html('reference/single/short', $reference_fragment->short_params);
        $html =~ s/^\s*//;
        $html =~ s/\s*$//;
        next unless $html;

        my $id = $reference->get_id();
        $id =~ s/\s+/\\s+/g;
	$g_transformations{'reference'}{$id} = _insert_links_pack($html);
    }
    my @types = keys %g_transformations;
    foreach my $type (@types) {
	foreach my $regex (keys %{ $g_transformations{$type} }) {
	    die "Duplicate id '$regex'" unless $g_transformations{$type}{$regex};
	    $g_transformations{'all'}{$regex} = _insert_links_pack($g_transformations{$type}{$regex});
	}
    }
}

# These hackey insert_*pack() functions keep the code from inserting links
# like this: <a href=mount-teneriffe-trailhead.html><a href=Mount-teneriffe.html>Mount Teneriffe</a> Trailhead</a>.
sub _insert_links_pack {
    my ($html) = @_;

    $html =~ s/(\w)(\w)/$1---NO-OP---$2---NO-OP---/g unless $html =~ /---NO-OP---/;
    $html =~ s/ /---SPACE---/g;

    return $html;
}

sub _insert_links_unpack {
    my ($html) = @_;

    $html =~ s/---NO-OP---//g;
    $html =~ s/---SPACE---/ /g;

    return $html;
}

sub insert_links {
    my ($html, %options) = @_;

    return '' unless length $html;

    # Double-inserting links can screw things up (like ---NO-OP---
    # strings are gone).
    die "Already inserted links in this" if $html =~ /LinksInserted/;

    make_link_transformations() unless keys %g_transformations;

    my $orig_html = $html;

    # Turn this:
    # http://xxxxxxxxxxxxxx 
    # into this:
    # <a href="http://xxxxxxxxxxxxxx">http://xxxxx...</a>
    $html =~ s{\b(https?://[^\s\)]+[^\s\.\)])}{_insert_links_pack(qq(<a href="$1">) . (length($1) > 30 ? substr($1, 0, 30) . "..." : $1) . qq(</a>))}ge;

    my $key = exists $options{'type'} ? $options{'type'} : 'all';

    foreach my $regex (sort { length($b) <=> length($a) } keys %{ $g_transformations{$key} }) {
	$html =~ s/$regex/$g_transformations{$key}{$regex}/g;
    }

    $html = _insert_links_unpack($html);

    # FIXME: Deprecate most of this link insertion code.  Keep insertion of URL links.
    if ($html ne $orig_html) {
        print "Inserting deprecated link in $orig_html\n";
    }

    return "<!-- LinksInserted -->$html";
}

=head1 Formatting text

Two consecutive newlines will turn into a <p> HTML tag.

=cut
sub htmlify {
    my ($html) = @_;

    return '' unless defined $html;

    $html = insert_links($html);

    $html =~ s/---NO-OP---//g;
    $html =~ s(\n\s*\n\s*)(<p />)g;

    return $html;
}

1;
