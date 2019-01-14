package Scramble::Controller::TripIndex;

# Creates the report index pages.  E.g., "Most Recent Trips" and "2017 Trips".

use strict;

use Scramble::Controller::ImageFragment ();

my $g_reports_on_index_page = 25;

sub new {
    my ($arg0, %args) = @_;

    my $self = { %args };

    return bless($self, ref($arg0) || $arg0);
}

sub create {
    my $self = shift;

    my @report_params = map { $self->get_report_params($_) } @{ $self->{reports} };

    my $template = Scramble::Template::create('trip/index');
    $template->param(Scramble::Template::common_params(),
                     change_year_dropdown_items => $self->{change_year_dropdown_items},
                     reports => \@report_params,
                     title => $self->{title});
    my $html = $template->output();

    Scramble::Misc::create("$self->{subdirectory}/$self->{id}.html", $html);
}

sub get_report_params {
    my $self = shift;
    my ($report) = @_;

    my $type = $report->get_type();
    my $name_html = $report->get_name();
    $name_html .= " $type" unless $name_html =~ /${type}$/;
    $name_html = $report->get_summary_name($name_html);
    my $date = $report->get_summary_date();

    my @images = $report->get_sorted_images();

    my @image_htmls = map {
        my $fragment = Scramble::Controller::ImageFragment->new($_);
        $fragment->create('no-description' => 1,
                          'no-lightbox' => 1,
                          'no-report-link' => 1)
    } @images;

    return {
        name_html => $name_html,
        date => $date,
        image_html_1 => $image_htmls[0],
        image_html_2 => $image_htmls[1],
        image_html_3 => $image_htmls[2]
    };
}

######################################################################
# Static

# home.html
sub create_all {
    my %reports;
    my $count = 0;
    my $latest_year = 0;
    my @reports = sort { Scramble::Model::Trip::cmp($b, $a) } Scramble::Model::Trip::get_all();
    foreach my $report (@reports) {
	my ($yyyy) = $report->get_parsed_start_date();
        $latest_year = $yyyy if $yyyy > $latest_year;

        push @{ $reports{$yyyy} }, $report;
        if ($count++ < $g_reports_on_index_page) {
            push @{ $reports{'index'} }, $report;
        }
    }

    foreach my $id (keys %reports) {
        my $title = $id eq 'index' ? "Most Recent Trips" : "$id Trips";
        $reports{$id} = {
            title => $title,
            reports => $reports{$id},
            subdirectory => "r",
        };
    }
    # The home page slowly became almost exactly the same as the
    # reports index page.
    #
    # FIXME: delete r/index.html?
    $reports{home} = { %{ $reports{index} } };
    $reports{home}{subdirectory} = "m";

    my @change_year_dropdown_items;
    foreach my $year (reverse sort keys %reports) {
        next unless $year =~ /^\d{4}$/;
        push @change_year_dropdown_items, {
            url => "../../g/r/$year.html",
            text => $year
        };
    }

    foreach my $id (keys %reports) {
        my $copyright_year = $id;
        if ($id !~ /^\d+$/) {
            $copyright_year = $latest_year;
        }

        my $page = Scramble::Controller::TripIndex->new(title => $reports{$id}{title},
                                                       copyright_year => $copyright_year,
                                                       id => $id,
                                                       reports => $reports{$id}{reports},
                                                       subdirectory => $reports{$id}{subdirectory},
                                                       change_year_dropdown_items => \@change_year_dropdown_items);
        $page->create();
    }
}

1;
