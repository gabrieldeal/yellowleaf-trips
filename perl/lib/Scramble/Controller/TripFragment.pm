package Scramble::Controller::TripFragment;

use strict;

use Scramble::Time ();

sub get_date_summary {
    my $trip = shift;

    my $date = $trip->get_start_date;
    my $num_days = $trip->get_num_days;
    if ($num_days > 1) {
        $date .= " ($num_days days)";
    }

    return $date;
}

1;
