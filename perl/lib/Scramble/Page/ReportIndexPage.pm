package Scramble::Page::ReportIndexPage;

# Creates the report index pages.  E.g., "Most Recent Trips" and "2017 Trips".

use strict;

my $g_reports_on_index_page = 25;


sub new {
    my ($arg0, %args) = @_;

    my $self = { %args };

    return bless($self, ref($arg0) || $arg0);
}

sub create {
    my $self = shift;

    my @report_params = map { $self->get_report_params($_) } @{ $self->{reports} };

    my $template = Scramble::Template::create('report/index');
    $template->param(change_year_dropdown_items => $self->{change_year_dropdown_items},
                     reports => \@report_params,
                     title => $self->{title});
    my $html = $template->output();

    Scramble::Misc::create
        ("$self->{subdirectory}/$self->{id}.html",
         Scramble::Misc::make_1_column_page(html => $html,
                                            title => $self->{title},
                                            'include-header' => 1,
                                            'no-title' => 1,
                                            'copyright-year' => $self->{copyright_year}));
}

sub get_report_params {
    my $self = shift;
    my ($report) = @_;

    my $type = $report->get_type();
    my $name_html = $report->get_name();
    $name_html .= " $type" unless $name_html =~ /${type}$/;
    $name_html = $report->get_summary_name($name_html);
    my $date = $report->get_summary_date();

    my $count = 0;
    my @images = ($report->get_sorted_images())[0..2];
    @images = grep { $_ } @images;
    my $image_htmls = Scramble::Misc::render_images_into_flow(images => \@images,
                                                              'no-description' => 1,
                                                              'no-lightbox' => 1,
                                                              'no-report-link' => 1);
    return {
        name_html => $name_html,
        date => $date,
        image_htmls => $image_htmls,
    };
}

######################################################################
# Static

# home.html
sub create_all {
    my %reports;
    my $count = 0;
    my $latest_year = 0;
    my @reports = sort { Scramble::Report::cmp($b, $a) } Scramble::Report::get_all();

    foreach my $report (@reports) {
	my ($yyyy) = $report->get_parsed_start_date();
        $latest_year = $yyyy if $yyyy > $latest_year;

        push @{ $reports{$yyyy} }, $report;
        if ($count++ < $g_reports_on_index_page) {
            push @{ $reports{'index'} }, $report;
        }
    }

    my @change_year_dropdown_items;
    foreach my $id (sort keys %reports) {
	my $title;
        if ($id eq 'index') {
	    $title = "Most Recent Trips";
        } else {
            push @change_year_dropdown_items, {
                url => "../../g/r/$id.html",
                text => $id
            };
	    $title = "$id Trips";
	}
        $reports{$id} = {
            title => $title,
            reports => $reports{$id},
            subdirectory => "r",
        };
    }
    @change_year_dropdown_items = reverse @change_year_dropdown_items;

    # The home page slowly became almost exactly the same as the
    # reports index page.
    $reports{home} = { %{ $reports{index} } };
    $reports{home}{subdirectory} = "m";

    foreach my $id (keys %reports) {
        my $copyright_year = $id;
        if ($id !~ /^\d+$/) {
            $copyright_year = $latest_year;
        }

        my $page = Scramble::Page::ReportIndexPage->new(title => $reports{$id}{title},
                                                        copyright_year => $copyright_year,
                                                        id => $id,
                                                        reports => $reports{$id}{reports},
                                                        subdirectory => $reports{$id}{subdirectory},
                                                        change_year_dropdown_items => \@change_year_dropdown_items);
        $page->create();
    }
}

1;
