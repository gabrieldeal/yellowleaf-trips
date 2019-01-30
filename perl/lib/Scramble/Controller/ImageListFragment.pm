package Scramble::Controller::ImageListFragment;

use strict;

sub html {
    my ($images) = @_;

    my @cells;
    push @cells, map {
        Scramble::Controller::ImageFragment->new($_)->params;
    } @$images;

    return '' unless @cells;

  # `float: left` breaks the favorite photos page.  Not having `float: left` breaks
  # photos in quad, list & location pages.
    my $params = {
        cells => \@cells,
        is_floated => 0,
    };

    return Scramble::Template::html('image/list', $params);
}

1;
