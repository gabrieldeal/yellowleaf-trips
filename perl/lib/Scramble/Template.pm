package Scramble::Template;

use strict;

use HTML::Template ();

sub dropdown_button {
    my (@items) = @_;

    my $template = HTML::Template->new(filename => 'perl/template/fragment/dropdown-button.html');
    $template->param(items => \@items);

    return $template->output();
}

1;
