package Scramble::Controller::ElevationFragment;

use strict;

sub format_elevation {
    my ($elevation) = @_;

    return '' unless $elevation;

    my %details = get_elevation_details($elevation);

    my $plus = $details{'plus'} ? "+" : "";
    my $approx_str = 'approx ';
    my $approx = $details{'approximate'} ? $approx_str : '';

    my $feet = sprintf("%s$plus feet", Scramble::Misc::commafy($details{feet}));
    my $meters = sprintf("%s$plus meters", Scramble::Misc::commafy($details{meters}));

    return "$approx$feet";
}

sub format_elevation_short {
    my ($elevations) = @_;

    my @formatted_elevations;
    foreach my $elevation (split(/, */, $elevations)) {
        my %details = get_elevation_details($elevation);
        push(@formatted_elevations,
             sprintf("%s%s%s%s",
                     $details{'approximate'} ? 'approx ' : '',
                     Scramble::Misc::commafy($details{'feet'}),
                     "'",
                     $details{'plus'} ? '+' : ''));
    }

    return join ", ", @formatted_elevations;
}

sub get_elevation_details {
    my ($elevation) = @_;

    my $orig_elev = $elevation;

    my $approx = ($elevation =~ s/^~//
                  ? 1
                  : 0);

    my $units = ($elevation =~ s/ (m|meters)$//
                 ? 'meters'
                 : 'feet');

    my $plus = ($elevation =~ s/\+\s*$//
                ? 1
                : 0);

    die "bad elevation '$orig_elev'" unless $elevation =~ /^-?\d+$/;

    my $meters;
    my $feet;
    if ($units eq 'meters') {
        $meters = $elevation;
        $feet = convert_meters_to_feet($elevation);
    } elsif ($units eq 'feet') {
        $meters = convert_feet_to_meters($elevation);
        $feet = $elevation;
    } else {
        die "Unrecognized elevation units '$units'";
    }

    return ('approximate' => $approx,
            'plus' => $plus,
            'units' => $units,
            'meters' => $meters,
            'feet' => $feet,
            'elevation' => $elevation);
}

my $g_conv_factor = .3048;
sub convert_meters_to_feet {
    my ($elevation) = @_;

    return int($elevation / $g_conv_factor);
}
sub convert_feet_to_meters {
    my ($elevation) = @_;

    return int($elevation * $g_conv_factor);
}

1;
