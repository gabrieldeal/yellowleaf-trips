package Scramble::Controller::ImageFragment;

use strict;

sub new {
    my ($arg0, $image) = @_;

    my $self = {
        image => $image,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create {
    my $self = shift;
    my (%options) = @_;

    return Scramble::Template::html('image/single', $self->params(%options));
}

sub params {
    my $self = shift;
    my (%options) = @_;

    my $image = $self->{image};
    my $is_video = $image->get_type eq 'movie';

    return {
        description => $image->get_description,
        enlarged_image_url => $image->get_enlarged_img_url,
        image_link_class => $options{'no-lightbox'} ? '' : 'lightbox-image',
        image_link_url => $options{'no-lightbox'} ? $image->get_trip_url : $image->get_enlarged_img_url,
        is_picture => !$is_video,
        is_video => $is_video,
        no_description => $options{'no-description'},
        no_trip_date => $options{'no-trip-date'},
        small_image_url => $image->get_url,
        trip_date => $image->get_capture_date || $image->get_date,
        trip_url => $image->get_trip_url,
        video_poster_url => $image->get_poster_url,
    };
}

1;
