package Scramble::Time;

use strict;

use Date::Manip ();

sub normalize_date_string {
    my ($date_string) = @_;

    my ($year, $mon, $day) = parse_date_and_time($date_string);

    return "$year/$mon/$day";
}

sub parse_date {
    my ($date) = @_;
    my ($year, $mon, $day) = ($date =~ /^(\d\d\d\d)[\/-](\d\d)[\/-](\d\d)$/);
    defined $day or die "Can't parse date '$date'";

    return ($year, $mon, $day);
}

sub parse_date_and_time {
  my ($t) = @_;

  my ($year, $mon, $day, $hour, $minute, $ampm) = ($t =~ m,^(\d\d\d\d)/(\d\d)/(\d\d)\s+(\d\d?):(\d\d)\s+(\w\w)\s*$,);
  if (! defined $day) {
    ($day, $hour, $minute, $ampm) = ($t =~ m,^(\d\d?):(\d\d)\s+(\w\w)\s*$,);
  }
  if (! defined $day) {
    my ($seconds);
    ($year, $mon, $day, $hour, $minute, $seconds) = ($t =~ m,^(\d\d\d\d)/(\d\d)/(\d\d)\s+(\d\d):(\d\d):(\d\d)(-\d\d:\d\d)?$,);
  }
  if (! defined $day) {
    my ($seconds);
    ($year, $mon, $day, $hour, $minute) = ($t =~ m,^(\d\d\d\d)/(\d\d)/(\d\d)\s+(\d\d):(\d\d)(-\d\d:\d\d)?$,);
  }
  if (! defined $day) {
    my ($seconds, $ms);
    ($year, $mon, $day, $hour, $minute, $seconds, $ms) = ($t =~ m,^(\d\d\d\d)/(\d\d)/(\d\d)\s+(\d\d):(\d\d):(\d\d)\.(\d+)$,);
  }
  if (! defined $day) {
    ($year, $mon, $day, $hour, $minute) = ($t =~ m,^(\d\d\d\d)/(\d\d)/(\d\d)\s+(\d\d?):(\d\d)$,);
  }
  if (! defined $day) {
    ($year, $mon, $day) = ($t =~ m,^(\d\d\d\d)[/-](\d\d)[/-](\d\d)$,);
  }

  if (! defined $day) {
    die "Unable to parse date/time '$t'";
  }

  return ($year, $mon, $day, $hour, $minute, $ampm);
}

sub get_days_since_1BC {
    my ($date) = @_;

    my ($year, $mon, $day) = parse_date_and_time($date);
    return Date::Manip::Date_DaysSince1BC($mon, $day, $year);
}

sub delta_dates {
    my ($start_date, $end_date) = @_;

    my $parsed_start_date = Date::Manip::ParseDate($start_date);
    my $parsed_end_date = Date::Manip::ParseDate($end_date);
    my $delta = Date::Manip::DateCalc($parsed_start_date, $parsed_end_date);
    my $minutes = Date::Manip::Delta_Format($delta, 0, "%mt");

    if (! defined $minutes or ! length $minutes) {
        die "Error parsing '$start_date' or '$end_date'";
    }
    if ($minutes <= 0) {
        die "The end date ($end_date) is not after start date ($start_date)";
    }
    if ($minutes !~ /^\d+(\.\d+)?$/) {
        die "Bad input '$start_date' '$end_date' ($minutes)";
    }

    return $minutes;
}

sub format_time {
    my ($h, $m) = @_;

    $h = 0 unless defined $h;
    $m = 0 unless defined $m;

    if ($h eq '?' or $m eq '?') {
	return "unknown";
    }

    my $time_in_minutes = $h * 60 + $m;

    my $days = int($time_in_minutes / (60 * 24));
    my $hours = int(($time_in_minutes % (60 * 24)) / 60);
    my $minutes = $time_in_minutes % 60;

    my $retval;
    if ($days > 0) {
	$retval .= "$days " . Scramble::Misc::pluralize($days, "day") . " ";
    }
    if ($hours > 0) {
	$retval .= "$hours " . Scramble::Misc::pluralize($hours, "hour") . " ";
    }
    if ($minutes > 0) {
	$retval .= "$minutes " . Scramble::Misc::pluralize($minutes, "minute");
    }

    Carp::confess "Nothing in '$h' and '$m'" unless defined $retval;

    return $retval;
}

1;
