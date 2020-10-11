package Scramble::Controller::PictureIndex;

use strict;

use Scramble::Controller::PictureListFragment ();

my $rating_threshold = 1;
my $g_num_pictures_threshold = 5;

# FIXME: break up this long function.
sub create_all {
    my ($writer) = @_;

    my $n_pictures_per_year = 50;
    my $n_per_date = 4;

    my @pictures = Scramble::Model::File::get_pictures_collection()->find('type' => 'picture');

    my %pictures;
    foreach my $picture (@pictures) {
	next unless $picture->get_rating() <= $rating_threshold;
        my ($year) = Scramble::Time::parse_date($picture->get_date());
	next unless $year > 2004;
        push @{ $pictures{$year}{pictures} }, $picture;
    }

    foreach my $year (keys %pictures) {
        my @pictures = @{ $pictures{$year}{pictures} };
        @pictures = n_per_date($n_per_date, @pictures);
        if (@pictures > $n_pictures_per_year) {
            @pictures = sort { $a->cmp($b) } @pictures;
            @pictures = @pictures[0..$n_pictures_per_year-1];
        }
        @pictures = sort { $b->get_date() cmp $a->get_date() } @pictures;

        if (@pictures < $g_num_pictures_threshold) {
            delete $pictures{$year};
            next;
        }

        $pictures{$year}{pictures} = \@pictures;
        $pictures{$year}{name} = $year;
    }

    my $latest_year = (sort {$a <=> $b } keys %pictures)[-1];
    $pictures{$latest_year}{name} = "current";

    my $filename_format = "m/p%s.html";

    my @change_year_dropdown_items;
    foreach my $year (reverse sort keys %pictures) {
        push @change_year_dropdown_items, {
            url => sprintf("../$filename_format", $pictures{$year}{name}),
            text => $year
        };
    }

    foreach my $year (sort keys %pictures) {
        my $pictures_html = Scramble::Controller::PictureListFragment::html($pictures{$year}{pictures});
	my $title = "My Favorite Photos of $year";

        my $template = Scramble::Template::create('picture/index');
        $template->param(change_year_dropdown_items => \@change_year_dropdown_items,
                         pictures_html => $pictures_html,
                         title => $title);

	my $name = $pictures{$year}{name};
        my $filename = sprintf($filename_format, $name);
        $writer->create($filename,
                        Scramble::Template::page_html(title => $title,
                                                      'include-header' => 1,
                                                      'no-title' => 1,
                                                      html => $template->output()));
    }
}

sub n_per_date {
    my ($n, @pictures) = @_;

    @pictures = sort { $a->cmp($b) } @pictures;

    my %trips;
    foreach my $picture (@pictures) {
        my $key = $picture->get_capture_date() || $picture->get_date();
        if (@{ $trips{$key} || [] } < $n) {
            push @{ $trips{$key} }, $picture;
        }
    }
    return map { @{ $trips{$_} } } keys %trips;
}

1;
