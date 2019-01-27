package Scramble::Controller::ImageListFragment;

use strict;

sub html {
    my (%args) = @_;

    my @cells;
    if ($args{htmls}) {
        push @cells, map { { html => $_} } grep($_, @{ $args{htmls} });
    }
    if ($args{images}) {
        push @cells, map {
            Scramble::Controller::ImageFragment->new($_)->params(%args);
        } @{ $args{images} };
    }

    return '' unless @cells;

  # `float: left` breaks the favorite photos page.  Not having `float: left` breaks
  # photos in quad, list & location pages.
    my $params = {
        cells => \@cells,
        is_floated => $args{'float-first'},
    };

    return Scramble::Template::html('image/list', $params);
}

1;
