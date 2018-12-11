package Scramble::Winter;

use strict;

sub get_winter_locations {
    my @locations;

    foreach my $report (Scramble::Report::get_all()) {
        next unless Scramble::Time::is_winter($report->get_start_date());

        foreach my $location ($report->get_location_objects()) {
            push @locations, $location;
        }
    }

    foreach my $location (Scramble::Location::get_visited(),
                          Scramble::Location::get_unvisited())
    {
        foreach my $reference ($location->get_references()) {
            my $season = Scramble::Reference::get_reference_attr('season', $reference);
            if (defined $season && $season eq 'winter') {
                push @locations, $location;
            }
        }
    }

    return @locations;
}

sub get_images {
    my @locations = @_;

    # Hack to get just a couple pics per report
    my @images;
    foreach my $location (@locations) {
        my @tmp_images = Scramble::Misc::get_images_for_locations($location);
        if (@tmp_images < 2) {
            push @images, @tmp_images;
        } else {
            push @images, @tmp_images[0, 1];
        }
    }

    my @winter_images;
    foreach my $image (@images) {
        push @winter_images, $image if Scramble::Time::is_winter($image->get_date());
    }

    return Scramble::Image::get_best_images(@winter_images);
}

sub make_body_html {
    my @locations = @_;

    my %area_objects;
    foreach my $location (@locations) {
        foreach my $area ($location->get_areas_collection()->get_all()) {
            next unless $area->get_is_recognizable_area();

            my $key = $area->get_id();
            $area_objects{$key}{'area'} = $area;
            push @{ $area_objects{$key}{'locations'} }, $location;
        }
    }

    my $html = "";
    foreach my $key (sort { $area_objects{$a}{'area'}->get_name() cmp $area_objects{$b}{'area'}->get_name() } keys %area_objects) {
        my @locations = Scramble::Location::dedup(@{ $area_objects{$key}{'locations'} });
        @locations = sort { $a->get_name() cmp $b->get_name() } @locations;

        my $area = $area_objects{$key}{'area'};

        $html .= sprintf("<h2>%s</h2><ul>",
                         $area->get_short_link_html());
        foreach my $location (@locations) {
            $html .= sprintf("<li>%s\n",
                             ($location->have_visited()
                              ? $location->get_short_link_html()
                              : $location->get_name()));
        }
        $html .= "</ul>";
    }

    return $html;
}

sub make_winter_page {
    my @locations = get_winter_locations();
    my @images = get_images(@locations);
    my $text_html = make_body_html(@locations);
    my $cells_html = Scramble::Misc::render_images_into_flow(htmls => [ $text_html ],
							     images => \@images);
    my $title = "Winter Destinations";

    my $html = <<EOT;
These are destinations that I have visited between Dec 22 and March 22 or destinations in ski or snowshoe guide books.
<br/>
$cells_html
EOT

    Scramble::Misc::create
	    ("m/winter.html",
	     Scramble::Misc::make_1_column_page(title => $title,
                                                'include-header' => 1,
						html => $html));
}

1;
