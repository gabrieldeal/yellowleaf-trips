package Scramble::Controller::TripPrivateIndex;

# Creates the trip index pages.  E.g., "Most Recent Trips" and "2017 Trips".

use strict;

use Scramble::Controller::PictureFragment ();
use Scramble::Controller::TripFragment ();

my $g_trips_on_index_page = 25;

sub new {
    my ($arg0, %args) = @_;

    my $self = { %args };

    return bless($self, ref($arg0) || $arg0);
}

sub create {
    my $self = shift;
    my ($writer) = @_;

    my @trips = grep { !$_->should_show } Scramble::Model::Trip::get_all();
    @trips = sort { Scramble::Model::Trip::cmp($b, $a) } @trips;

    my @trip_params = map { $self->get_trip_params($_) } @trips;

    my $template = Scramble::Template::create('trip/index');
    $template->param(Scramble::Template::common_params(),
                     trips => \@trip_params,
                     title => "Unlinked Trips");
    my $html = $template->output();

    $writer->create("m/unlinked-trips.html", $html);
}

sub get_trip_params {
    my $self = shift;
    my ($trip) = @_;

    my $date = Scramble::Controller::TripFragment::get_date_summary($trip);

    my @pictures = $self->get_pictures($trip);

    my @picture_htmls = map {
        my $fragment = Scramble::Controller::PictureFragment->new($_);
        $fragment->html('no-description' => 1,
                        'no-lightbox' => 1,
                        'no-trip-date' => 1,
                        'no-trip-link' => 1)
    } @pictures;

    return {
        date => $date,
        picture_html_1 => $picture_htmls[0],
        picture_html_2 => $picture_htmls[1],
        picture_html_3 => $picture_htmls[2],
        name => $trip->get_name,
        state => $trip->get_state ne 'done' ? $trip->get_state : undef,
        url => $trip->get_trip_page_url,
    };
}

sub get_pictures {
    my $self = shift;
    my ($trip) = @_;

    return () unless $trip->should_show();

    my @pictures = grep { $_->is_summary } $trip->get_picture_objects();
    if (!@pictures) {
        @pictures = $trip->get_picture_objects;
    }

    @pictures = sort { $a->get_rating() <=> $b->get_rating() } @pictures;

    return sort { $a->cmp_datetime($b) } grep(defined, @pictures[0..2]);
}

1;
