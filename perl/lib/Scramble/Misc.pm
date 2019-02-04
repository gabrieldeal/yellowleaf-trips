package Scramble::Misc;

use strict;

use Exporter 'import';
use Getopt::Long ();
use IO::File ();
use Scramble::Logger ();
use URI::Encode ();

our @EXPORT_OK = qw(
    get_options
    my_system
);

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

# FIXME: Get rid of this.
my $g_output_directory;
sub get_output_directory { $g_output_directory }
sub set_output_directory { $g_output_directory = $_[0] }

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

sub usage {
    my ($options) = @_;

    my ($prog) = ($0 =~ /([^\/]+)$/);

    return sprintf("Usage: $prog [ OPTIONS ]\nOptions:\n\t--%s\n",
                   join("\n\t--", @$options));
}

sub get_options {
    my (%args) = @_;

    my %results = %{ $args{defaults} };

    local $SIG{__WARN__};
    if (! Getopt::Long::GetOptions(\%results, @{ $args{options} })
        || $results{help})
    {
        print usage($args{options});
        exit 1;
    }

    foreach my $required (@{ $args{required} }) {
        if (! exists $results{$required}) {
            print "Missing --$required\n";
            print usage($args{options});
            exit 1;
        }
    }

    if (exists $results{timezone}) {
        $ENV{TZ} = $results{timezone};
    }

    return %results;
}

sub my_system {
    my (@command) = @_;

    print "Running @command\n";
    return if 0 == system @command;

    die "Command exited with failure code ($?): @command";
}

1;
