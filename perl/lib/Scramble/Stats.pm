package Scramble::Stats;

use strict;

sub display_short_trips {
    my $max_hours = 4;
    print "Trips shorter than $max_hours hours:\n";

    my $short_reports = Scramble::Model::Trip::get_shorter_than($max_hours);
    foreach my $report (sort { Scramble::Model::Trip::cmp_by_duration($a, $b) } @$short_reports) {
        my $minutes = $report->get_waypoints()->get_car_to_car_delta();
        my $hours = $minutes / 60;
        printf("    %2.3f hours, %s, %s\n", $hours, $report->get_start_date(), $report->get_name());
    }
    print "\n";
}

sub display_party_stats {
  my %stats;
  my %people;
  foreach my $report (Scramble::Model::Trip::get_all()) {
    my $party = $report->_get_optional_content('party');
    next unless $party;

    my @members = map { $_->{name} } @{ $party->{member} || [] };
    push @members, grep /\S/, split(/\n/, $party->{content}) if $party->{content};

    my ($yyyy, $mm, $dd) = Scramble::Time::parse_date($report->get_start_date());

    die "$yyyy/$mm/$dd " . Data::Dumper::Dumper($party) unless $party->{size};

    $stats{$mm}{trip_count}++;
    $stats{$mm}{person_count} += $party->{size};

    foreach my $member (@members) {
      my $name;
      if (ref $member) {
	$name = $member->{name};
      } else {
	$name = $member;
      }
      $name =~ s/\s*\([\w\s]*\)\s*$//;
      $name =~ s/^\s*(.*?)[\s\.]*$/$1/i;
      $name = "Hilary Clark" if $name =~ /seahorse/i or $name =~ /hilary s/i;
      $name = "Chris Clark" if $name =~ /chilidog/i;
      $name = "Kate (DnR) Hoch" if $name =~ /DnR/ or $name =~ /drop.n.roll/i or $name =~ /Kate.*Hoch/;
      $name = "Jacob (Daybreaker) Sperati" if $name =~ /jacob.*sperati/i or $name =~ /daybreaker/i;
      $name = "Brad (Mister Fox) White" if $name =~ /(mr\.?|mister)\s*fox/i;
      $name = "Courtney (Rocklocks) Braun" if $name =~ /rock\s*locks/i;
      $name = "Deb (Topsy Turvy) Brown" if $name =~ /^deb\b.*\bbrown$/i or $name =~ /\btopsy\s*turvy\b/i;
      $name =~ s/^Mom$/Bonnie Deal/i;
      $name =~ s/^Boni Deal$/Bonnie Deal/i;
      $name = "Laurie Cullen" if $name =~ /^Laurie C$/;
      $name =~ s/^Carla S$/Carla Schauble/i;
      $name =~ s/^Carla Shauble$/Carla Schauble/i;
      $name =~ s/^David Deal$/Dave Deal/i;
      $name =~ s/^Matt B$/Matt Burton/i;
      $name = "Yana Radenska" if $name =~ /\byana\b/i;
      $name = "Jiri Richter" if $name =~ /\bjiri\b/i;
      $name = "Lindsay Malone" if $name =~ /\bLindsay Malone\b/i;
      $name = "Brian Walkenhauer" if $name =~ /^(Brian|Bryan) Walk/;
      $name = "Janet Putz" if $name =~ /\bputz\b/i;
      $name = "Tazz" if $name =~ /\btazz\b/i || $name eq 'Ann Arnoldy';
      $name = "Lynn Graff" if $name eq "Lynn Graf";
      $name = "Mike Helminger" if $name =~ /\biron\b/i || $name eq "Mike Hemlinger" || $name =~ /^Mike H$/;
      $name = "Tom Nanevicz" if $name =~ /\bTom N\b/i || $name =~ /\bGeoTom\b/i;
      $name = "Bruno Reinys" if $name eq "Bruno R";
      $name = "Matt Burton" if $name =~ /\bmatt\b/i && $name =~ /\bburton\b/;
      $name = "David Suhr" if $name eq "David Sur";
      $name = "Atsuko Yamaguchi" if $name =~ /\batsuko\b/i;
      $name =~ s/^Brett D$/Brett Dyson/i;
      $name =~ s/^Bruno$/Bruno Reinys/i;
      $people{$name}{trips}++;
      $people{$name}{days} += $report->get_num_days();
    }
  }

  foreach my $name (sort { $people{$a}{trips} <=> $people{$b}{trips} } keys %people) {
    printf("%d %d %s\n", $people{$name}{trips}, $people{$name}{days}, $name);
  }

  foreach my $mm (sort { $a <=> $b } keys %stats) {
    printf("$mm: %.2f people on average in %d trips\n",
	   $stats{$mm}{person_count} / $stats{$mm}{trip_count},
	   $stats{$mm}{trip_count});
  }
}

1;
