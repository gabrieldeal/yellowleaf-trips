package Scramble::Controller::GeekeryPage;

use strict;

use Scramble::Htmlify ();
use Scramble::Misc ();

sub get_list_stats {
    my @stats;
    foreach my $list (Scramble::Model::List::get_all()) {
	my $climbed_count = 0;
        foreach my $list_location ($list->get_locations) {
            my $location_object = $list_location->get_location_object;
	    next unless $location_object && $location_object->have_visited();
	    $climbed_count++;
	}
	next unless $climbed_count;

        my $total = $list->get_locations;
        my $percent = 100 * $climbed_count / $total;
        push @stats, {
            list_name => $list->get_name,
            list_url => $list->get_url,
            percent => int($percent),
            total_count => $total,
        };
    }

    @stats = reverse sort { $a->{percent} <=> $b->{percent} } @stats;

    return (
        list_stats_rows => \@stats,
    );
}

sub get_yearly_stats {
    my @column_keys = qw(
        year
        total_peaks
        total_trips
        climbing_trips
        trail_run_trips
        total_days
        climbing_days
        trail_run_days
    );

    my %stats;
    foreach my $trip (Scramble::Model::Trip::get_all()) {
	my $date = $trip->get_start_date();
	my ($year) = ($date =~ /^(\d\d\d\d)\//);

        if (! exists $stats{$year}) {
            $stats{$year} = { map { ($_ => 0) } @column_keys };
            $stats{$year}{year} = $year;
        }

	my $ndays = $trip->get_num_days();
	$stats{$year}{total_days} += $ndays;
	$stats{$year}{total_trips}++;
        if ($trip->get_type() =~ /crag|climb|boulder/) {
            $stats{$year}{climbing_days} += $ndays;
            $stats{$year}{climbing_trips}++;
        } elsif ($trip->get_type() =~ /trail run/) {
            $stats{$year}{trail_run_days} += $ndays;
            $stats{$year}{trail_run_trips}++;
        }

        my @locations = grep { $_->is_peak } $trip->get_location_objects();
        $stats{$year}{total_peaks} += @locations;
    }

    my $this_year  = Date::Manip::UnixDate("today", "%Y");
    if (exists $stats{$this_year}) {
        my $day_of_year = Date::Manip::UnixDate("today", "%j");
        foreach my $column_key (@column_keys) {
            my $new_value;
            if ($column_key eq 'year') {
                $new_value = "$this_year (projected)";
            } else {
                $new_value = 365 / $day_of_year * $stats{$this_year}{$column_key};
            }
            $stats{$this_year}{$column_key} = $new_value;
        }
    }

    my $column_names = [ map {
                           { name => join(' ', map { ucfirst } split('_', $_)) }
                         } @column_keys ];

    my @rows;
    foreach my $year (sort keys %stats) {
        push @rows, {
            values => [ map { { value => $stats{$year}{$_} } } @column_keys ],
        };
    }

    return (
        yearly_stats_columns => $column_names,
        yearly_stats_rows => \@rows,
    );
}

sub get_total_climbed {
    my $unique_count = 0;
    my $summit_count = 0;
    my %climbed;
    foreach my $location (Scramble::Model::Location::get_visited()) {
        next if ! ($location->is_peak
                   || (defined $location->get_prominence()
                       && $location->get_prominence() > 400));
        my $count = scalar(grep { $_->get_state() eq 'done' } Scramble::Model::Trip::get_trips_for_location($location));
        next unless $count;
	$unique_count++;
        $summit_count += $count;
        if ($count > 5) {
            $climbed{$location->get_id} = {
                count => $count,
                location => $location,
            };
        }
    }

    my @most_climbed;
    foreach my $id (sort { $climbed{$b}{count} <=> $climbed{$a}{count} } keys %climbed) {
        my $location = $climbed{$id}{location};
        push @most_climbed, {
            count => $climbed{$id}{count},
            name => $location->get_name,
            url => $location->get_url,
        };
    }

    return (unique_peaks => $unique_count,
            total_peaks => $summit_count,
            repeat_count => $summit_count - $unique_count,
            most_climbed_peaks => \@most_climbed);
}

sub create {
    my ($writer) = @_;

    my $params = {
        get_yearly_stats,
        get_list_stats,
        get_total_climbed,
    };
    my $html = Scramble::Template::html('geekery/page', $params);

    $writer->create("m/geekery.html",
                    Scramble::Template::page_html(title => "Geekery",
                                                  'include-header' => 1,
                                                  html => $html));
}

1;
