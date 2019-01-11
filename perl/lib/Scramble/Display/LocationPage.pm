package Scramble::Display::LocationPage;

use strict;

use Scramble::Misc ();
use Scramble::Template ();

# FIXME: Convert to a template.

sub new {
    my ($arg0, $location) = @_;

    my $self = {
        location => $location,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create_all {
    my @locations = (Scramble::Model::Location::get_visited(),
                     Scramble::Model::Location::get_unvisited());
    @locations = sort { lc($a->get_filename()) cmp lc($b->get_filename()) } @locations;

    foreach my $location (@locations) {
        my $page = Scramble::Display::LocationPage->new($location);
        $page->create();
    }
}

sub create {
    my $self = shift;

    my $location = $self->{location};

    my $location_name_note = ($location->get_is_unofficial_name()
			      ? " (unofficial name)"
			      : '');
    my $prominence = Scramble::Misc::make_optional_line(qq(<b><a href="http://www.peaklist.org/theory/theory.html">Clean Prominence</a>:</b> %s<br>),
							\&Scramble::Misc::format_elevation,
							$location->get_prominence());
    my $quad_links = $self->get_quads_html();
    my $county_html = Scramble::Misc::make_optional_line("<b>County:</b> %s<br>",
							 $self->get_counties_html());
    my $elevation = Scramble::Misc::make_colon_line("Elevation", $self->get_formatted_elevation());
    my $description = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("<h2>Description</h2>%s",
										 $location->get_description()));

    my $reports_html = Scramble::Misc::make_optional_line("<h2>Trip Reports and References</h2> %s",
                                                          $self->get_reports_for_location_html());
    my $recognizable_areas_html = $self->get_recognizable_areas_html();

    my $state_html = Scramble::Misc::make_colon_line("State", $self->get_state_html());

    my $aka_html = Scramble::Misc::make_optional_line("<b>AKA:</b> %s<br>",
						      $self->get_aka_names_html());
    my $title = sprintf("Location: %s", $location->get_name());
    my $naming_origin = Scramble::Misc::htmlify(Scramble::Misc::make_optional_line("<h2>Name origin</h2> %s",
                                                                                   $location->get_naming_origin()));
    my $text_html = <<EOT;
$aka_html
$elevation
$prominence
$state_html
$county_html
$recognizable_areas_html
$quad_links

$reports_html
$description
$naming_origin
EOT

    my @htmls = ($text_html);
    my $map_html =  $self->get_embedded_google_map_html();
    push @htmls, $map_html if $map_html;

    my $cells_html = Scramble::Misc::render_images_into_flow('htmls' => \@htmls,
                                                             'float-first' => 1,
                                                             'images' => [ $location->get_picture_objects() ]);

    my $html = <<HTML;
$cells_html
<br clear="all" />
HTML

    Scramble::Misc::create(sprintf("l/%s", $location->get_filename()),
                           Scramble::Misc::make_1_column_page(title => "$title$location_name_note",
							      'include-header' => 1,
                                                              html => $html,
							      'no-add-picture' => 1,
                                                              'enable-embedded-google-map' => $Scramble::Misc::gEnableEmbeddedGoogleMap));
}

sub get_aka_names_html {
    my $self = shift;

    my @aka_names = $self->{location}->get_aka_names();
    my $delim = grep(/,/, @aka_names) ? ';' : ',';

    return join("$delim ", @aka_names);
}

sub get_recognizable_areas_html {
    my $self = shift;

    my @areas = $self->{location}->get_recognizable_areas();
    my @names = map { $_->get_short_name() } @areas;

    return Scramble::Misc::make_colon_line("In", join(", ", @names));
}

sub get_quads_html {
    my $self = shift;

    return '' unless $self->{location}->get_quad_objects();
    my $links = join(", ", map { $_->get_short_name() } $self->{location}->get_quad_objects());
    my $title = sprintf("USGS %s", Scramble::Misc::pluralize(scalar($self->{location}->get_quad_objects()),
							     "quad"));
    return Scramble::Misc::make_colon_line($title, $links);
}

sub get_counties_html {
    my $self = shift;

    my @htmls = map { $_->get_short_name() } $self->{location}->get_county_objects();

    return @htmls ? join(", ", @htmls) : undef;
}

sub get_state_html {
    my $self = shift;

    if (! $self->{location}->get_state_object()) {
      return undef;
    }
    return $self->{location}->get_state_object()->get_short_name();
}

sub get_embedded_google_map_html {
    my $self = shift;

    return '' unless $self->{location}->get_longitude();

    return Scramble::Misc::get_multi_point_embedded_google_map_html([ $self->{location} ]);
}

sub get_reports_for_location_html {
    my $self = shift;

    my $location = $self->{location};

    my @references_html = Scramble::Display::ReferenceFragment::get_page_references_html($location->get_references());

    my @reports = Scramble::Model::Report::get_reports_for_location($location);
    return undef unless @reports || @references_html;

    foreach my $report (@reports) {
        next unless $report->should_show();
        push @references_html, sprintf("$Scramble::Misc::gSiteName: %s",
                                       $self->get_report_link_html($report));
    }

    return '<ul><li>' . join('</li><li>', @references_html) . '</li></ul>';
}

sub get_report_link_html {
    my $self = shift;
    my ($report) = @_;

    my $date = $report->get_summary_date();
    my $name = $report->get_summary_name();
    my $image_html = $self->get_summary_image_html($report) || '';
    my $type = $report->get_type();

    return <<EOT;
<div class="report-thumbnail">
    <div class="report-thumbnail-image">$image_html</div>
    <div class="report-thumbnail-title">$name</div>
    <div class="report-thumbnail-date">$date</div>
    <div class="report-thumbnail-type">$type</div>
</div>
EOT
}

sub get_summary_image_html {
    my $self = shift;
    my ($report) = @_;

    my $size = 125;

    my @image_htmls;
    foreach my $image_obj ($report->get_sorted_images()) {
        if ($image_obj) {
            my $image_html = sprintf(qq(<img width="$size" onload="Yellowleaf_main.resizeThumbnail(this, $size)" src="%s">),
                                     $image_obj->get_url());
            $image_html = $report->link_if_should_show($image_html);
            push @image_htmls, $image_html;
        }
    }

    return $image_htmls[0];
}

sub get_formatted_elevation {
    my $self = shift;
    return $self->_get_formatted_elevation(\&Scramble::Misc::format_elevation);
}
sub get_short_formatted_elevation {
    my $self = shift;
    return $self->_get_formatted_elevation(\&Scramble::Misc::format_elevation_short);
}
sub _get_formatted_elevation {
    my $self = shift;
    my ($format_func) = @_;

    if (defined $self->{location}->get_elevation()) {
	return $format_func->($self->{location}->get_elevation());
    }

    return undef;
}

1;
