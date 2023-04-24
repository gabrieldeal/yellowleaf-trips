package Scramble::Controller::PictureFragment;

use strict;

sub new {
    my ($arg0, $picture) = @_;

    my $self = {
        picture => $picture,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub html {
    my $self = shift;
    my (%options) = @_;

    return Scramble::Template::html('picture/single', $self->params(%options));
}

sub params {
    my $self = shift;
    my (%options) = @_;

    my $picture = $self->{picture};

    my $is_video = $picture->get_type eq 'movie';
    my $is_sound = $picture->get_type eq 'sound';
    my $video_poster_url = $is_video ? $picture->get_poster_url : undef;
    my $sound_url = $is_sound ? $picture->get_sound_url : undef;

    return {
        description => $picture->get_description,
        picture_link_class => $options{'no-lightbox'} ? '' : 'lightbox-image',
        picture_link_url => $options{'no-lightbox'} ? $picture->get_trip_url : $picture->get_enlarged_img_url,
        is_picture => !$is_video && !$is_sound,
        is_sound => $is_sound,
        is_video => $is_video,
        no_description => $options{'no-description'} || $picture->get_trip->should_hide_locations,
        no_trip_date => $options{'no-trip-date'},
        small_picture_url => $picture->get_url,
        sound_url => $sound_url,
        trip_date => $picture->get_capture_date || $picture->get_date,
        trip_url => $picture->get_trip_url,
        video_url => $is_video ? $picture->get_enlarged_img_url : undef,
        video_poster_url => $video_poster_url,
    };
}

1;
