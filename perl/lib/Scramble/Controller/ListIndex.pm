package Scramble::Controller::ListIndex;

use strict;

use Scramble::Model::List ();
use Scramble::Misc ();

sub create {
    my @lists;
    foreach my $list (Scramble::Model::List::get_all()) {
        if ($list->should_skip) {
            next;
        }

        push @lists, {
            name => $list->get_name,
            url => $list->get_url
        };
    }

    my $template = Scramble::Template::create('list/index');
    $template->param(lists => \@lists);
    my $html = $template->output();

    Scramble::Misc::create("li/index.html",
                           Scramble::Template::page_html(title => "Peak Lists",
                                                         html => $html,
                                                         'include-header' => 1));
}

1;
