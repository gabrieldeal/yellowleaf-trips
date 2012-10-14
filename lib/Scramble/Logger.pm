package Scramble::Logger;

use strict;

my $g_verbose = 0;

sub set_verbose { $g_verbose = $_[0] }

sub verbose {
    if ($g_verbose) {
	print @_;
        print "\n" unless $_[-1] =~ /\n$/;
    }
}


1;
