package Scramble::Controller::TripFragment;

use strict;

use Scramble::Time ();

sub get_date_summary {
    my $trip = shift;

    my $date = $trip->get_start_date;
    if (defined $trip->get_end_date) {
        my $start_day = Scramble::Time::get_days_since_1BC($trip->get_start_date);
        my $end_day = Scramble::Time::get_days_since_1BC($trip->get_end_date);
        my $num_days = 1 + $end_day - $start_day;
        $date .= " ($num_days days)";
    }

    return $date;
}

1;
