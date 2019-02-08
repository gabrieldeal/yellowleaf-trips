package Scramble::SpellCheck;

use strict;

use Scramble::Logger ();
use Spell ();

my %gWords;

sub check_spelling {
    my ($dictionary_dir) = @_;

    initialize($dictionary_dir);
    _add_words();

    my @misspelled = _check_spelling_in_all_documents();

    if (@misspelled) {
        die "Misspelled:\n\t" . join("\n\t", @misspelled) . "\n";
    }
}

sub _add_words {
    Scramble::Logger::verbose("Adding words to the dictionary...");
    my $location_collection = Scramble::Model::Location::get_all();
    foreach my $location ($location_collection->get_all()) {
        add_words($location->get_name());
        foreach my $aka ($location->get_aka_names()) {
            add_words($aka);
        }
    }

    my @reference_ids = map { $_->get_id() } Scramble::Model::Reference::get_all();
    foreach my $id (@reference_ids) {
        add_words($id);
    }
}

sub _check_spelling_in_all_documents {
    Scramble::Logger::verbose("Checking spelling...");

    my @misspelled;

    foreach my $trip (Scramble::Model::Trip::get_all()) {
        my @texts;
        push @texts, $trip->get_route() if defined $trip->get_route();
        push @texts, $trip->get_name();
        push @texts, $trip->get_type();
        foreach my $text (@texts) {
            push @misspelled, _check_spelling_in_text($text, $trip->get_filename(), $trip->get_start_date());
        }
    }

    foreach my $image (Scramble::Model::Image::get_all_images_collection()->get_all()) {
        foreach my $text ($image->get_description(), $image->get_of(), $image->get_from(), $image->get_section_name()) {
            push @misspelled, _check_spelling_in_text($text, $image->get_trip_files_src_dir(), $image->get_date());
        }
    }

    return @misspelled;
}

sub _check_spelling_in_text {
    my ($text, $name, $date) = @_;

    return unless defined $text;

    my @misspelled = check($text);
    return unless @misspelled;

    my $message = $name . ": @misspelled.";
    if (defined $date && $date gt '2007/07/01') {
        return ($message);
    } else {
        print "Ignoring misspelled words from $message\n";
        return ();
    }
}

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
    foreach my $word (split /[\s\/-]+/, $text) {
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

    return "" if $word =~ /^(\w\.)+$/; # skip acronyms

    $word =~ s/\&[a-z]{3};//;

    # remove climb ratings like 5.10d:
    $word =~ s/\b(5\.)?1[0-5][abcd]\b//;

    $word =~ s/\b(1st|2nd|3rd|[4-9]th|\d+th)\b//;

    # Strip decades like "1970s":
    $word =~ s/\b(18|19)\d\ds\b//;

    # Strip trail names like 1009a:
    $word =~ s/\b\d+[abc]\b//;

    $word =~ s/^[\W_]+//;

    # Strip punctuation like "tarn.":
    $word =~ s/[:;,\.!\?\)'"+]+$//;

    return '' if $word =~ /^\d+$/;
    return '' if $word =~ /^\s+$/;

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

    $text =~ s,\bhttps?://\S+,,g;

    # Strip letters like "A" in "Plan A:":
    $text =~ s/\b[A-Z]://g;

    chomp $text;
    $text = lc $text;

    my @misspelled;
    for my $word (grep {/[^\W\d_]/} split_words($text)) {
        $word = strip_word($word);
        next if $word eq '';

        if (! grep { exists $gWords{$_} } possibilities($word)) {
            push @misspelled, $word;
        }
    }

    return sort @misspelled;
}

1;
