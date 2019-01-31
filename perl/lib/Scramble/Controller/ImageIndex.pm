package Scramble::Controller::ImageIndex;

use strict;

use Scramble::Controller::ImageListFragment ();

my $g_pictures_by_year_threshold = 1;

# FIXME: break up this long function.
sub create_all {
    my $n_pictures_per_year = 50;
    my $n_per_date = 4;

    my @images = Scramble::Model::Image::get_all_images_collection()->find('type' => 'picture');

    my %pictures;
    foreach my $image (@images) {
	next unless $image->get_rating() <= $g_pictures_by_year_threshold;
        my ($year) = Scramble::Time::parse_date($image->get_date());
	next unless $year > 2004;
        push @{ $pictures{$year}{images} }, $image;
    }

    foreach my $year (keys %pictures) {
        my @images = @{ $pictures{$year}{images} };
        @images = n_per_date($n_per_date, @images);
        if (@images > $n_pictures_per_year) {
            @images = sort { Scramble::Model::Image::cmp($a, $b) } @images;
            @images = @images[0..$n_pictures_per_year-1];
        }
        @images = sort { $b->get_date() cmp $a->get_date() } @images;
        $pictures{$year}{images} = \@images;
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
        my $images_html = Scramble::Controller::ImageListFragment::html($pictures{$year}{images});
	my $title = "My Favorite Photos of $year";

        my $template = Scramble::Template::create('image/index');
        $template->param(change_year_dropdown_items => \@change_year_dropdown_items,
                         images_html => $images_html,
                         title => $title);

	my $name = $pictures{$year}{name};
        my $filename = sprintf($filename_format, $name);
	Scramble::Misc::create($filename,
			       Scramble::Template::page_html(title => $title,
                                                             'include-header' => 1,
                                                             'no-title' => 1,
                                                             html => $template->output()));
    }
}

sub n_per_date {
    my ($n, @images) = @_;

    @images = sort { Scramble::Model::Image::cmp($a, $b) } @images;

    my %trips;
    foreach my $image (@images) {
        my $key = $image->get_capture_date() || $image->get_date();
        if (@{ $trips{$key} || [] } < $n) {
            push @{ $trips{$key} }, $image;
        }
    }
    return map { @{ $trips{$_} } } keys %trips;
}

1;
