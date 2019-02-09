package Scramble::Model::File::Picture;

use strict;

use Scramble::Model::File ();

our @ISA = qw(Scramble::Model::File);

# FIXME: Split up videos and pictures?

sub new {
    my $arg0 = shift;
    my (%args) = @_;

    my $self = { %args };
    bless $self, ref($arg0) || $arg0;

    $self->SUPER::initialize;
    $self->{chronological_order} = 0 unless exists $self->{chronological_order};

    if (defined $self->{date}) {
        $self->{date} = Scramble::Time::normalize_date_string($self->{date});
    }

    return $self;
}

sub get_chronological_order { $_[0]->{chronological_order} }
sub get_enlarged_filename { $_[0]->{'large-filename'} }
sub get_enlarged_img_url { $_[0]->_get_url($_[0]->get_enlarged_filename) }
sub get_from { $_[0]->{from} || '' }
sub get_of { $_[0]->{'of'} } # undefined means we don't know. Empty string means it is not of any known location.
sub get_poster { $_[0]->{poster} } # Video-specific
sub get_section_name { $_[0]->{'section-name'} }
sub in_chronological_order { $_[0]->{in_chronological_order} }

sub get_filenames {
    my $self = shift;

    my @files = ($self->get_filename);

    if ($self->get_type eq 'movie') {
        push @files, $self->get_poster if $self->get_poster;
    } elsif ($self->get_enlarged_filename) {
        push @files, $self->get_enlarged_filename;
    } # else: this is an old trip like 2005-03-05-Goat-Mtn

    return @files;
}

sub get_poster_url {
    my $self = shift;

    if (!$self->get_poster) {
        return '';
    }

    return $self->_get_url($self->get_poster);
}

sub get_rating {
    my $self = shift;

    # Rating v3:
    # 1 - One of my favorites
    # 2 - Pretty
    # 3 - Part of the story

    # Rating v2:
    # 1 - One of my best photos ever.  Very few photos in this category.
    # 2 - Great photo that stands on its own.
    # 3 - Used to distinguish my favorite pics from a trip, where most of the pics in the trip are 3.1.
    # 3.1 - Nice photo, but needs the story to be useful.  Most photos are in this category.
    # 4 - Included only for the story.

    # Rating v1:
    # 1 best
    # 100 worst

    if (defined $self->{rating}) {
        return $self->{rating};
    }
    return 3;
}

sub cmp {
    my $self = shift;
    my ($other) = @_;

    if (! defined $self->get_rating && ! defined $other->get_rating) {
        return 0;
    }
    if (! defined $self->get_rating) {
        return -1;
    }
    if (! defined $other->get_rating) {
        return 1;
    }
    if ($self->get_rating == $other->get_rating) {
        return _cmp_date($other, $self); # Newest first
    }
    return $self->get_rating <=> $other->get_rating;
}

sub _cmp_date {
    my ($picture_a, $picture_b) = @_;

    my $date_a = $picture_a->get_date;
    my $date_b = $picture_b->get_date;
    if ($picture_a->get_datetime && $picture_b->get_datetime) {
        $date_a = $picture_a->get_datetime;
        $date_b = $picture_b->get_datetime;
    }

    if (! defined $date_a) {
        if (! defined $date_b) {
            return 0;
        } else {
            return -1;
        }
    }
    if (! defined $date_b) {
        return 1;
    }

    return $date_a cmp $date_b;
}

1;
