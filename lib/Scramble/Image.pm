package Scramble::Image;

use strict;

use File::Basename ();
use Scramble::Collection ();
use HTML::Entities ();

my $g_pictures_by_year_threshold = 1;
my $g_image_rating_threshold = 1;
my $g_pics_dir = "pics";
my $g_collection = Scramble::Collection->new();

sub _copy {
    my ($file1, $file2, $dir, $target_dir) = @_;

    foreach my $file ($file1, $file2) {
        next unless defined $file;
        my $source = "$dir/$file";
        my $target = "$target_dir/$file";
        my $source_size = (stat($source))[7] or die "Error getting size '$source': $!";
        my $target_size = (stat($target))[7];
        if (defined $target_size && $source_size == $target_size) {
            next;
        }
        Scramble::Logger::verbose("cp $source $target_dir\n");
        system("cp \"$source\" \"$target_dir\"") == 0 or die "Can't copy '$source' to '$target_dir': $!";
    }
}
sub copy {
    my $output_image_dir = Scramble::Misc::get_output_directory() . "/$g_pics_dir/";

    File::Path::mkpath([$output_image_dir], 0, 0755);
    foreach my $image (glob "data/common-images/*.{gif,ico,png}") {
        system("cp \"$image\" \"$output_image_dir\"") == 0 or die "Can't copy '$image' to '$output_image_dir': $!";
    }

    foreach my $image (get_all_images_collection()->get_all()) {
        my $target_dir = "$output_image_dir/" . $image->get_subdirectory();
        File::Path::mkpath([$target_dir], 0, 0755);
        _copy($image->get_filename(),
              $image->get_enlarged_filename(),
              $image->get_source_directory(),
              $target_dir);
    }
}

sub new_from_attrs {
    my $arg0 = shift;
    my ($args) = @_;

    my $self = { %$args };
    bless $self, ref($arg0) || $arg0;

    $self->{'type'} = 'picture' unless exists $self->{'type'};
    $self->{'subdirectory'} = File::Basename::basename($self->{'source-directory'});
    $self->{'chronological-order'} = 0 unless exists $self->{'chronological-order'};
    foreach my $key (qw(subdirectory thumbnail-filename type source-directory)) {
        die "Missing '$key': ", Data::Dumper::Dumper($self)
            unless defined $self->{$key};
    }

    $self->{'description'} = $self->{'description'} ? ucfirst($self->{'description'}) : '';

    if (defined $self->{'date'}) {
	$self->{'date'} = Scramble::Time::normalize_date_string($self->{'date'});
    }

    return $self;
}

sub get_id { $_[0]->get_source_directory() . "|" . $_[0]->get_filename() }
sub get_chronological_order { $_[0]->{'chronological-order'} }
sub in_chronological_order { $_[0]->{'in-chronological-order'} }
sub get_source_directory { $_[0]->{'source-directory'} }
sub get_filename { $_[0]->{'thumbnail-filename'} }
sub get_enlarged_filename { $_[0]->{'large-filename'} }
sub get_subdirectory { $_[0]->{'subdirectory'} }
sub get_section_name { $_[0]->{'section-name'} }

# This should be "report id".
sub get_date { $_[0]->{'date'} } # optional for maps that are not for a particular trip

sub get_description { $_[0]->{'description'} }
sub get_of { $_[0]->{'of'} } # undefined means we don't know. Empty string means it is not of any known location.
sub get_from { $_[0]->{'from'} || '' }
sub get_url { sprintf("../../$g_pics_dir/%s/%s", $_[0]->get_subdirectory(), $_[0]->get_filename()) }
sub get_full_url { sprintf("http://yellowleaf.org/scramble/$g_pics_dir/%s/%s", $_[0]->get_subdirectory(), $_[0]->get_filename()) }
sub get_report_url { $_[0]->{'report-url'} }
sub set_report_url { $_[0]->{'report-url'} = $_[1] }
sub get_pager_url { $_[0]->{'pager-url'} }
sub set_pager_url { $_[0]->{'pager-url'} = $_[1] }
sub get_should_skip_report { $_[0]->{'skip-report'} }
sub get_type { $_[0]->{'type'} }

sub get_capture_date {
    my $self = shift;

    my $capture_date = $self->{'capture-timestamp'};
    return undef unless defined $capture_date;

    my ($date) = ($capture_date =~ m,^(\d\d\d\d/\d\d/\d\d),);
    return $date;
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

sub get_best_images {
    my @images = @_;

    @images = Scramble::Misc::dedup(@images);
    @images = sort { Scramble::Image::cmp($a, $b) } @images;

    my $max = 50;
    if (@images > $max) {
        @images = @images[0 .. $max-1];
    }

    return @images;
}

sub get_enlarged_html_url {
    my $self = shift;

    return undef unless defined $self->get_enlarged_filename();

    return "../../g/" . $self->get_enl_html_filename();
}

sub get_enlarged_img_url {
    my $self = shift;

    return undef unless defined $self->get_enlarged_filename();

    return sprintf("../../$g_pics_dir/%s/%s",
                   $self->get_subdirectory,
                   $self->get_enlarged_filename());
}

sub get_description_html { 
    my $self = shift;

    # have to calculate lazily b/c of circular dependencies with Scramble::Location

    if (! $self->{'description-html'}) {
	$self->{'description-html'} = Scramble::Misc::htmlify($self->get_description());
    }

    return $self->{'description-html'};
}

sub get_map_reference {
    my $self = shift;

    return { 'name' => $self->get_description(),
	     'URL' => $self->get_url(),
	     'id' => 'routeMap', # used by Scramble::Reference
	     'type' => ($self->{'noroute'} 
			? "Online map"
			: "Online map with route drawn on it"),
	 };
}

sub get_video_tag {
    my $self = shift;
    my (%options) = @_;

    return sprintf(qq(<video width="320" height="240" controls>
                   <source src="%s" type="video/mp4">
                   </video>),
                   $self->get_enlarged_img_url());
}

sub get_img_tag {
    my $self = shift;
    my (%options) = @_;
    
    my $enlarged = $options{'enlarged'};
    my $border = (! $enlarged && $self->get_enlarged_filename()) ? 2 : 0;
    return sprintf(qq(<img %s src="%s" alt="Image of %s" border="$border" hspace="1" vspace="1">),
                   (exists $options{'image-attributes'} ? $options{'image-attributes'} : ''),
                   $enlarged ? $self->get_enlarged_img_url() : $self->get_url(),
                   HTML::Entities::encode_entities($self->get_description()));
}

sub get_html {
    my $self = shift;
    my (%options) = @_;

    my $img_html;
    if ($self->get_type() eq 'movie') {
        $img_html = $self->get_video_tag(%options);
    } else {
        $img_html = $self->get_img_tag(%options);
        if ($self->get_enlarged_html_url()) {
            my $url;
            if ($options{'pager-links'} && $self->get_pager_url()) {
                $url = $self->get_pager_url();
            } else {
                $url = $self->get_enlarged_html_url();
            }
            $img_html = sprintf(qq(<a href="%s">$img_html</a>), $url);
        }
    }

    my $description = Scramble::Misc::htmlify($self->get_description());
    my $report_link = '';
    if ($self->get_report_url() && ! $options{'no-report-link'}) {
	$report_link = $self->get_report_link_html();
    }

    return Scramble::Misc::make_cell_html(content => $img_html,
					  description => $description,
					  link => $report_link);
}

sub get_report_link_html {
    my $self = shift;

    return sprintf(qq(<a href="%s">%s</a>),
		   $self->get_report_url(),
		   $self->get_capture_date() || $self->get_date());
}

sub cmp {
  my ($a, $b) = @_;

  if (! defined $a->get_rating() && ! defined $b->get_rating()) {
    return 0;
  }
  if (! defined $a->get_rating()) {
    return -1;
  }
  if (! defined $b->get_rating()) {
    return 1;
  }
  if ($a->get_rating() == $b->get_rating()) {
    return cmp_date($b, $a); # Newest first
  }
  return $a->get_rating() <=> $b->get_rating();
}

######################################################################
# Statics
######################################################################

sub get_all_images_collection { $g_collection }

sub read_images_from_report {
    my ($directory, $report) = @_;

    my $date = $report->get_start_date();
    my ($year, $month, $day) = Scramble::Time::parse_date($date);

    my $in_chronological_order = $report->_get_optional('files', 'in-chronological-order');
    if (defined($in_chronological_order) && '' eq $in_chronological_order) {
	die "images.in-chronological-order is empty";
    }

    my @images;
    my $chronological_order = 0;
    foreach my $image_xml (@{ $report->_get_optional('files', "file") || [] }) {
        next if $image_xml->{skip};
        push @images, Scramble::Image->new_from_attrs({ 'date' => "$year/$month/$day",
                                                        'source-directory' => $directory,
                                                        'chronological-order' => $chronological_order++,
                                                        'in-chronological-order' => $in_chronological_order,
                                                        %$image_xml,
                                                    });
    }

    $g_collection->add(@images);
    return @images;
}

sub make_enl_picture_pages {
    foreach my $image (sort { cmp_date($a, $b) } $g_collection->get_all()) {
        $image->make_enl_page();
    }
}

sub cmp_date {
  my ($image_a, $image_b) = @_;

  if (! defined $image_a->get_date()) {
    if (! defined $image_a->get_date()) {
      return 0;
    } else {
      return -1;
    }
  }
  if (! defined $image_b->get_date()) {
    return 1;
  }

  return $image_a->get_date() cmp $image_b->get_date();
}

sub get_enl_html_filename {
    my $self = shift;

    my $date = $self->get_date();
    $date =~ s,/,-,g;
    my $file = $self->get_filename();
    $file =~ s/\.[^\.]*$//;

    return "enl/$date-$file.html";
}

sub make_enl_page {
    my $self = shift;

    if (! $self->get_enlarged_filename()) {
        return;
    }

    my $output_filename = $self->get_enl_html_filename();

    my $image_html = $self->get_img_tag('enlarged' => 1);

    my $description = $self->get_description() || "Untitled";

    my $description_html = $description;
    my $link_html = '';
    if ($self->get_report_url()) {
        $link_html = $self->get_report_link_html();
    }

    my $html = <<EOT;
<h1>$description_html <div class="report-link">$link_html</div></h1>
$image_html
EOT

    my $page_html
        = Scramble::Misc::make_1_column_page('title' => $description,
                                             'date' => $self->get_date(),
                                             'html' => $html,
                                             'no-add-picture' => 1,
                                             'no-links-box' => 1);
    Scramble::Misc::create($output_filename, $page_html);
}

sub n_per_date {
    my ($n, @images) = @_;

    @images = sort { Scramble::Image::cmp($a, $b) } @images;

    my %trips;
    foreach my $image (@images) {
        my $key = $image->get_date();
        if (@{ $trips{$key} || [] } < $n) {
            push @{ $trips{$key} }, $image;
        }
    }
    return map { @{ $trips{$_} } } keys %trips;
}
sub make_images_by_year_page {
    my $n_pictures_per_year = 50;
    my $n_per_date = 4;

    my @images = Scramble::Image::get_all_images_collection()->find('type' => 'picture');

    my %pictures;
    foreach my $image (@images) {
	next unless $image->get_rating() <= $g_pictures_by_year_threshold;
        my ($year) = Scramble::Time::parse_date($image->get_date());
	next unless $year > 2004;
        push @{ $pictures{$year}{images} }, $image;
    }

    foreach my $year (keys %pictures) {
        my @images = @{ $pictures{$year}{images} };
        @images = n_per_date($n_per_date, @images);
        if (@images > $n_pictures_per_year) {
            @images = sort { Scramble::Image::cmp($a, $b) } @images;
            @images = @images[0..$n_pictures_per_year-1];
        }
        @images = sort { $b->get_date() cmp $a->get_date() } @images;
        $pictures{$year}{images} = \@images;
        $pictures{$year}{name} = $year;
    }

    my $latest_year = (sort {$a <=> $b } keys %pictures)[-1];
    $pictures{$latest_year}{name} = "current";

    my $filename_format = "m/p%s.html";

    my @header;
    foreach my $year (sort keys %pictures) {
        push @header, sprintf(qq(<a href="../$filename_format">$year</a>),
                              $pictures{$year}{name});
    }
    my $header = join(", ", @header) . "<p>";

    foreach my $year (sort keys %pictures) {
	my $images_html = Scramble::Misc::render_images_into_flow(images => $pictures{$year}{images});
	my $title = "My Favorite Photos of $year";

	my $html = <<EOT;
<h1>$title</h1>
$header
$images_html

<br clear="both">
<br>
$header
EOT

	my $name = $pictures{$year}{name};
        my $filename = sprintf($filename_format, $name);
	Scramble::Misc::create($filename,
			       Scramble::Misc::make_1_column_page(title => $title,
								  'include-header' => 1,
								  html => $html));
    }
}

1;
