package Scramble::Controller::ListIndex;

use strict;

use Scramble::Model::List ();
use Scramble::Misc ();

# FIXME: Refactor display code into a template.

sub create {
    my @lists;
    foreach my $list_xml (Scramble::Model::List::get_all_lists()) {
        if ($list_xml->{'skip'}) {
            next;
        }

        push @lists, {
            name => $list_xml->{name},
            url => $list_xml->{URL}
        };
    }

    my $template = Scramble::Template::create('list/index');
    $template->param(lists => \@lists);
    my $html = $template->output();

    Scramble::Misc::create("li/index.html",
                           Scramble::Misc::make_1_column_page(title => "Peak Lists",
                                                              html => $html,
                                                              'include-header' => 1));
}

1;
