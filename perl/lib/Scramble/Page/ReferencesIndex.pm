package Scramble::Page::ReferencesIndex;

use strict;

use Scramble::Misc ();
use Scramble::Model::Reference ();
use Scramble::Page::ReferenceFragment ();

sub create {
    my $references_html;
    my @references = values %{ Scramble::Model::Reference::get_all() };
    foreach my $reference (sort { Scramble::Model::Reference::cmp_references($a, $b) } @references) {
	next unless $reference->{'name'};
	next unless $reference->{'link'};
        $references_html .= sprintf("<li>%s</li>",
                                    Scramble::Page::ReferenceFragment::get_reference_html($reference));
    }

    Scramble::Misc::create("m/references.html",
                           Scramble::Misc::make_1_column_page(title => "Links",
                                                              html => qq(<ul>$references_html</ul>),
                                                              'include-header' => 1));
}

1;
