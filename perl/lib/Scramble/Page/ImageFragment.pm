package Scramble::Page::ImageFragment;

use strict;

use HTML::Entities ();

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

    my $image = $self->{image};

    my $img_html;
    if ($image->get_type() eq 'movie') {
        $img_html = $self->get_video_tag();
    } else {
        $img_html = $self->get_img_tag(%options);
        if ($image->get_enlarged_img_url()) {
            my $css_class = 'lightbox-image';
            my $url = $image->get_enlarged_img_url();
            if ($options{'no-lightbox'}) {
                $css_class = '';
                $url = $image->get_report_url();
            }

            my $title = HTML::Entities::encode_entities($image->get_description());

            $img_html = sprintf(qq(<a class="$css_class" title="$title" href="%s">$img_html</a>), $url);
        }
    }

    my $description = '';
    if (! $options{'no-description'}) {
        $description = Scramble::Misc::htmlify($image->get_description());
    }

    my $report_link = '';
    if ($image->get_report_url() && ! $options{'no-report-link'}) {
	$report_link = $image->get_report_link_html();
    }

    return Scramble::Misc::make_cell_html(content => $img_html,
					  description => $description,
					  link => $report_link);
}

sub get_video_tag {
    my $self = shift;

    my $poster = '';
    if ($self->{image}->get_poster()) {
        $poster = sprintf(qq(poster="%s" preload="none"), $self->{image}->get_poster_url());
    }

    return sprintf(qq(<video $poster width="320" height="180" controls>
                   <source src="%s" type="video/mp4">
                   </video>),
                   $self->{image}->get_enlarged_img_url());

}

sub get_img_tag {
    my $self = shift;
    my (%options) = @_;
    
    my $enlarged = $options{'enlarged'};
    my $border = (! $enlarged && $self->{image}->get_enlarged_filename()) ? 2 : 0;
    return sprintf(qq(<img %s src="%s" alt="Image of %s" border="$border" hspace="1" vspace="1">),
                   (exists $options{'image-attributes'} ? $options{'image-attributes'} : ''),
                   $enlarged ? $self->{image}->get_enlarged_img_url() : $self->{image}->get_url(),
                   HTML::Entities::encode_entities($self->{image}->get_description()));
}

1;
