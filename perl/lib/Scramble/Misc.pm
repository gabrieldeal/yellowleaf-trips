package Scramble::Misc;

use strict;

use IO::File ();
use Scramble::Logger ();
use URI::Encode ();

sub dedup {
    my (@dups) = @_;

    # Preserve the order of the items in @dups.
    my %seen;
    my @deduped;
    foreach my $item (@dups) {
        push @deduped, $item unless $seen{$item};
        $seen{$item} = 1;
    }

    return @deduped;
}

sub pluralize {
    my ($number, $word) = @_;

    if ($number =~ /^\?/) {
	return "${word}s";
    }

    my $suffix = ($word =~ /s$/ ? "es" : "s");

    return $number != 1 ? "$word$suffix" : $word;
}

# FIXME: Deprecate this.
sub make_optional_line {
    my ($format, $arg2, $arg3) = @_;

    if (ref($arg2) eq 'CODE') {
	return '' unless defined $arg3;
	my $value = $arg2->(@_[2..$#_]);
	return (defined $value ? sprintf($format, $value) : '');
    }
    
    if (! $arg3) {
	return $arg2 ? sprintf($format, $arg2) : '';
    }
    
    my ($key, $hash) = ($arg2, $arg3);
    
    if (! exists $hash->{$key}) {
	return "";
    }
    
    return sprintf($format, $hash->{$key});
}

sub slurp {
    my ($path) = @_;

    return do {
        open(my $fh, $path) or die "Can't open $path: $!";
        local $/ = undef;
        <$fh>;
    };
}

# FIXME: Move to Scramble::Template?
sub create {
    my ($path, $html) = @_;

    $path = get_output_directory() . "/g/$path";
    Scramble::Logger::verbose "Creating $path\n";
    my $ofh = IO::File->new($path, "w") 
	or die "Unable to open '$path': $!";
    $ofh->print($html) or die "Failed to write to '$path': $!";
    $ofh->close() or die "Failed to flush to '$path': $!";
}

######################################################################
# Config

my $g_output_directory;
sub get_output_directory { $g_output_directory }
sub set_output_directory { $g_output_directory = $_[0] }

######################################################################

# FIXME: Change data so this is not needed.
sub numerify_longitude {
    my ($lon) = @_;

    if ($lon =~ /^-\d+\.\d+$/) {
	return $lon;
    } elsif ($lon =~ /^(\d+\.\d+) (E|W)$/) {
	return $2 eq 'W' ? -$1 : $1;
    } else {
	die "Unable to parse longitude '$lon'";
    }
}
sub numerify_latitude {
    my ($lat) = @_;

    my ($num, $hemisphere);
    if (($num, $hemisphere) = ($lat =~ /^(\d+\.\d+) (N|S)$/)) {
        return $hemisphere eq 'S' ? -$num : $num;
    } elsif ($lat =~ /^-?\d+\.\d+$/) {
        return $lat
    } else {
        die "Unable to parse latitude '$lat'";
    }
}

# FIXME: change data so this is not needed.
sub numerify {
    my ($string) = @_;

    my $orig_str = $string;
    $string =~ s/^~//; # elevation
    $string =~ s/,//g; # elevation
    $string =~ s/ m$//; # elevation
    $string =~ s/\+$//; # elevation

    $string =~ s/\s+\((approx )?[\d,]+ meters\)$//; # elevation
    $string =~ s/\s+feet//; # elevation

    $string =~ s/ N$//; # latitude
    $string =~ s/^(\d+\.\d+) W/-$1/; # longitude

    die "Can't numerify '$orig_str': $string" unless $string =~ /^-?\d+(\.\d+)?( m)?$/;

    return $string;
}

sub commafy {
    my ($number) = @_;
    1 while $number =~ s/(\d)(\d\d\d)(,|$)/$1,$2/g;
    return $number;					 
}

sub sanitize_for_filename {
    my ($filename) = @_;

    $filename =~ s/[^\w\.]//g;

    return $filename;
}

sub choose_interactive {
    my @choices = @_;

    die "No choices given" unless @choices;

    foreach my $i (0 .. $#choices) {
        print qq[$i) $choices[$i]{name}\n];
    }

    my $chosen_index;
    do {
        print "Which? ";
        chomp($chosen_index = <STDIN>);
    } while ($chosen_index !~ /^\d+$/ || $chosen_index < 0 || $chosen_index > $#choices);

    return $choices[$chosen_index]{value}
}

1;
