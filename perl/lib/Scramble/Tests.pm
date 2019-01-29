package Scramble::Tests;

use strict;

use Scramble::Misc ();
use Scramble::Time ();

sub assert {
    my ($a, $msg) = @_;

    defined $msg or die "Need message";

    $a or die "Assertion failed ($msg)";
}

sub assert_equals {
    my ($a, $b) = @_;

    die if ref($a) || ref($b);
    $a eq $b or die "Got '$a' expected '$b'";
}

sub run {
    foreach my $test_name (keys %{Scramble::Tests::}) {
	next unless $test_name =~ /^test/;
	Scramble::Logger::verbose("Running $test_name()\n");
	$Scramble::Tests::{$test_name}->();
    }
}

######################################################################

sub test_assert {
    assert_equals("a", "a");
    eval {
	assert_equals("a", "x");
    };
    $@ || die "Assert failed";

    eval {
	assert_equals([], []);
    };
    $@ || die "Assert failed";
}

sub test_files_exist {
    my @files = qw(
                   li/middleforkpeakselevation.html
		   .htaccess
		   );

    my $outdir = Scramble::Misc::get_output_directory();
    foreach my $file (@files) {
	my $path = "$outdir/g/$file";
	assert(-f "$outdir/g/$file", "Missing $path");
    }
}

sub test_insert_links {
    my %tests = ("Mount Teneriffe" => "Mount Teneriffe", #qq(<a href="../../g/l/Mount-Teneriffe.html">Mount Teneriffe</a>),
		 "Mount Teneriffe Trailhead" => "Mount Teneriffe Trailhead", #qq(<a href="../../g/l/Mount-Teneriffe-Trailhead.html">Mount Teneriffe Trailhead</a>),
                 "middleforkpeaks" => qq(<a href="../li/middleforkpeakselevation.html">Middle Fork Snoqualmie River peaks</a>),
		 "http://www.amazon.com/o/asin/B00000ASIN" => qq(<a href="http://www.amazon.com/o/asin/B00000ASIN">http://www.amazon.com/o/asin/B...</a>),
		 "http://www.wta.org/" => qq(<a href="http://www.wta.org/">http://www.wta.org/</a>),
                 "mountaineersScramblingClass" => qq(<a href="http://www.mountaineers.org/">Mountaineer&#39;s scrambling course</a>),
		 
		 "wta" => qq(<a href="http://www.wta.org/~wta/cgi-bin/wtaweb.pl?7+tr">Washington Trails Association</a>),
		 );

    while (my ($text, $expected) = each %tests) {
        assert_equals(Scramble::Htmlify::insert_links($text),
		      "<!-- LinksInserted -->$expected");
    }
}

sub test_delta_dates {
    assert_equals(5, Scramble::Time::delta_dates("5 AM", "5:05 AM"));
}

1;
