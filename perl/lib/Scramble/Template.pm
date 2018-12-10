package Scramble::Template;

use strict;

use HTML::Template ();

sub create {
    my ($name) = @_;

    my $filename = "perl/template/$name.html";

    return HTML::Template->new(filename => $filename,
                               default_escape => 'html');
}

1;
