package Scramble::Controller::TripIndex;

# Creates the trip index pages.  E.g., "Most Recent Trips" and "2017 Trips".

use strict;

use Scramble::Controller::ImageFragment ();

my $g_trips_on_index_page = 25;

sub new {
    my ($arg0, %args) = @_;

    my $self = { %args };

    return bless($self, ref($arg0) || $arg0);
}

sub create {
    my $self = shift;

    my @trip_params = map { $self->get_trip_params($_) } @{ $self->{trips} };

    my $template = Scramble::Template::create('trip/index');
    $template->param(Scramble::Template::common_params(),
                     change_year_dropdown_items => $self->{change_year_dropdown_items},
                     trips => \@trip_params,
                     title => $self->{title});
    my $html = $template->output();

    Scramble::Misc::create("$self->{subdirectory}/$self->{id}.html", $html);
}

sub get_trip_params {
    my $self = shift;
    my ($trip) = @_;

    my $name_html = $trip->get_name();
    $name_html = $trip->get_summary_name($name_html);
    my $date = $trip->get_summary_date();

    my @images = $trip->get_sorted_images();

    my @image_htmls = map {
        my $fragment = Scramble::Controller::ImageFragment->new($_);
        $fragment->create('no-description' => 1,
                          'no-lightbox' => 1,
                          'no-trip-link' => 1)
    } @images;

    return {
        name_html => $name_html,
        date => $date,
        image_html_1 => $image_htmls[0],
        image_html_2 => $image_htmls[1],
        image_html_3 => $image_htmls[2]
    };
}

######################################################################
# Static

# home.html
sub create_all {
    my %trips;
    my $count = 0;
    my $latest_year = 0;
    my @trips = sort { Scramble::Model::Trip::cmp($b, $a) } Scramble::Model::Trip::get_all();
    foreach my $trip (@trips) {
	my ($yyyy) = $trip->get_parsed_start_date();
        $latest_year = $yyyy if $yyyy > $latest_year;

        push @{ $trips{$yyyy} }, $trip;
        if ($count++ < $g_trips_on_index_page) {
            push @{ $trips{'index'} }, $trip;
        }
    }

    foreach my $id (keys %trips) {
        my $title = $id eq 'index' ? "Most Recent Trips" : "$id Trips";
        $trips{$id} = {
            title => $title,
            trips => $trips{$id},
            subdirectory => "r",
        };
    }
    # The home page slowly became almost exactly the same as the
    # trips index page.
    #
    # FIXME: delete r/index.html?
    $trips{home} = { %{ $trips{index} } };
    $trips{home}{subdirectory} = "m";

    my @change_year_dropdown_items;
    foreach my $year (reverse sort keys %trips) {
        next unless $year =~ /^\d{4}$/;
        push @change_year_dropdown_items, {
            url => "../../g/r/$year.html",
            text => $year
        };
    }

    foreach my $id (keys %trips) {
        my $copyright_year = $id;
        if ($id !~ /^\d+$/) {
            $copyright_year = $latest_year;
        }

        my $page = Scramble::Controller::TripIndex->new(title => $trips{$id}{title},
                                                       copyright_year => $copyright_year,
                                                       id => $id,
                                                       trips => $trips{$id}{trips},
                                                       subdirectory => $trips{$id}{subdirectory},
                                                       change_year_dropdown_items => \@change_year_dropdown_items);
        $page->create();
    }
}

1;
