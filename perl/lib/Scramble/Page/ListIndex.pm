package Scramble::Page::ListIndex;

use strict;

use Scramble::Model::List ();
use Scramble::Misc ();

# FIXME: Refactor display code into a template.

sub create {
    my $index_html;
    foreach my $list_xml (Scramble::Model::List::get_all_lists()) {
        if ($list_xml->{'skip'}) {
            next;
        }

        # FIXME: The if & else seem nearly identical...
        if (! $list_xml->{'no-display'}) {
            $index_html .= sprintf(qq(<li>%s</li>), Scramble::Model::List::make_list_link($list_xml));
	} elsif ($list_xml->{'URL'}) {
            $index_html .= sprintf(qq(<li><a href="%s">%s</li>),
                                   $list_xml->{URL},
                                   $list_xml->{name});
        }
    }

    $index_html = <<EOT;
<ul>
$index_html
</ul>
EOT

    Scramble::Misc::create("li/index.html",
                           Scramble::Misc::make_1_column_page(title => "Peak Lists",
                                                              html => $index_html,
                                                              'include-header' => 1));
}

1;
