package Spell;

use strict;

my %gWords;

sub initialize {
    my ($dir) = @_;

    my @files = glob "$dir/*" or die "No dictionaries in '$dir'";
    for my $file (@files) {
        open(IN,$file) or die "Could not open dictionary '$file': $!\n";
        my @words = map { (split(/\s+/, lc($_))) } <IN>;
        chomp @words;
        @gWords{@words} = ();
    }
}

sub split_words {
    my ($text) = @_;

    my @words;
    foreach my $word (split /[\s-\/]+/, $text) {
        $word =~ s/'s$//;
        push @words, $word;
    }

    return @words;
}

sub add_words {
    my ($text) = @_;

    foreach my $word (split_words($text)) {
        $gWords{strip_word(lc($word))} = 1;
    }
}

sub strip_word {
    my ($word) = @_;

    # remove climb ratings like 5.10d:
    $word =~ s/\b(5\.)?1[0-5][abcd]\b//;

    $word =~ s/\b(1st|2nd|3rd|[4-9]th|\d+th)\b//;

    # Strip decades like "1970s":
    $word =~ s/\b(18|19)\d\ds\b//;

    # Strip trail names like 1009a:
    $word =~ s/\b\d+[abc]\b//;

    $word =~ s/^[\W_]+//;
    $word =~ s/[\W\d_]+$//;

    return $word;

}

sub possibilities {
    my ($word) = @_;

    my @regexes = ('(.*)s',
                   '(.*s)es',
                   '(.*)ing',
                   '(.*)ed',
                   '(.*)able',
                   '(.*)ing',
                   'un(.*)',
                  );

    my @possibilites;
    foreach my $regex (@regexes) {
        if ($word =~ /^$regex$/) {
            push @possibilites, $1;
        }
    }

    my $word1 = $word;
    if ($word1 =~ s/ies$/y/i) {
        push @possibilites, $word1;
    }

    return ($word, @possibilites);
}

sub check {
    my ($text) = @_;

    $text =~ s,\bhttp://\S+,,g;

    # Strip letters like "A" in "Plan A:":
    $text =~ s/\b[A-Z]://g;

    chomp $text;
    $text = lc $text;

    my @misspelled;
    for my $word (grep {/[^\W\d_]/} split_words($text)) {
        $word = strip_word($word);

        if (! grep { exists $gWords{$_} } possibilities($word)) {
            push @misspelled, $word;
        }
    }

    return sort @misspelled;
}

1;
