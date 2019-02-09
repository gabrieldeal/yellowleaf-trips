package Scramble::Controller::ImageFragment;

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

    return Scramble::Template::html('image/single', $self->params(%options));
}

sub params {
    my $self = shift;
    my (%options) = @_;

    my $picture = $self->{picture};

    my $is_video = $picture->get_type eq 'movie';
    my $video_poster_url = $is_video ? $picture->get_poster_url : undef;

    return {
        description => $picture->get_description,
        enlarged_image_url => $picture->get_enlarged_img_url,
        image_link_class => $options{'no-lightbox'} ? '' : 'lightbox-image',
        image_link_url => $options{'no-lightbox'} ? $picture->get_trip_url : $picture->get_enlarged_img_url,
        is_picture => !$is_video,
        is_video => $is_video,
        no_description => $options{'no-description'},
        no_trip_date => $options{'no-trip-date'},
        small_image_url => $picture->get_url,
        trip_date => $picture->get_capture_date || $picture->get_date,
        trip_url => $picture->get_trip_url,
        video_poster_url => $video_poster_url,
    };
}

1;
