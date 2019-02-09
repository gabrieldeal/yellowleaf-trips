package Scramble::Controller::PictureListFragment;

use strict;

sub html {
    my ($pictures) = @_;

    my @cells;
    push @cells, map {
        Scramble::Controller::PictureFragment->new($_)->params;
    } @$pictures;

    return '' unless @cells;

  # `float: left` breaks the favorite photos page.  Not having `float: left` breaks
  # photos in quad, list & location pages.
    my $params = {
        cells => \@cells,
        is_floated => 0,
    };

    return Scramble::Template::html('picture/list', $params);
}

1;
