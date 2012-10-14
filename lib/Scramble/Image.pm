package Scramble::Image;

use strict;

use File::Basename ();
use Scramble::Collection ();

my $g_pictures_by_year_threshold = 1;
my $g_image_rating_threshold = 1;
my $g_pics_dir = "pics";
my $g_collection;

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
    $self->{'noroute'} = 0 unless exists $self->{'noroute'};
    $self->{'subdirectory'} = File::Basename::basename($self->{'source-directory'});
    $self->{'chronological-order'} = 0 unless exists $self->{'chronological-order'};

    foreach my $key (qw(subdirectory filename noroute type source-directory))
    {
        die "Missing '$key': ", Data::Dumper::Dumper($self)
            unless defined $self->{$key};
    }

    if (! exists $self->{'enlarged-filename'}) {
        my $glob = $self->{'source-directory'} . "/" . $self->{'filename'};
        $glob =~ s/\.\w+$//;
        $glob .= "-[Ee][Nn][Ll].*";
        $glob =~ s/ /\\ /g;
        my @match = glob($glob);
        die "Too many matches for '$glob': @match" if @match > 1;
        die "No match ($glob): " . Data::Dumper::Dumper($self) if @match == 0 && $glob =~ /2010-04-30-/;
        if (@match) {
            $self->{'enlarged-filename'} = $match[0];
            $self->{'enlarged-filename'} =~ s(.*/)();
        }
    }

    if ($self->{'title'}) {
	$self->{'title'} = ucfirst($self->{'title'});
    } elsif ($self->get_of()) {
	$self->{'title'} = ucfirst($self->get_of());
	if ($self->{'from'}) {
	    $self->{'title'} .= " from " . $self->{'from'};
	}
    } else {
        $self->{'title'} = '';
    }

    if (defined $self->{'date'}) {
	$self->{'date'} = Scramble::Time::normalize_date_string($self->{'date'});
    }

    return $self;
}

sub new_from_path {
    my $arg0 = shift;
    my ($path) = @_;

    my $self = {};

    $self->{'source-directory'} = File::Basename::dirname($path);
    $self->{'filename'} = File::Basename::basename($path);

    $self->{'title'} = $self->{'filename'};
    $self->{'noroute'} = ($self->{'title'} =~ s/-noroute-map/-map/);
    $self->{'title'} =~ s/\..*$//; # filename extension
    $self->{'title'} =~ s/^\d+n?-*//;
    $self->{'title'} = Scramble::Misc::make_path_into_location($self->{'title'});

    my ($yyyy, $mm, $dd) = ($path =~ m,/(\d\d\d\d)[/-](\d\d)[/-](\d\d)[/-],);
    $self->{'date'} = "$yyyy/$mm/$dd" if defined $dd;

    $self->{'type'} = ($self->{'filename'} =~ /-map\./
		       ? "map"
		       : "picture");

    ($self->{'rating'}) = ($self->{'filename'} =~ /^(\d\d)/);

    return $arg0->new_from_attrs($self);
}

sub get_trip_id { $_[0]->{'trip-id'} }
sub get_areas { @{ $_[0]->{'areas'} || [] } }
sub get_chronological_order { $_[0]->{'chronological-order'} }
sub in_chronological_order { $_[0]->{'in-chronological-order'} }
sub get_source_directory { $_[0]->{'source-directory'} }
sub get_filename { $_[0]->{'filename'} }
sub get_enlarged_filename { $_[0]->{'enlarged-filename'} }
sub get_subdirectory { $_[0]->{'subdirectory'} }
sub get_date { $_[0]->{'date'} } # optional for maps that are not for a particular trip
sub get_title { $_[0]->{'title'} }
sub get_of { $_[0]->{'of'} || '' }
sub get_from { $_[0]->{'from'} || '' }
sub get_url { sprintf("../../$g_pics_dir/%s/%s", $_[0]->get_subdirectory(), $_[0]->get_filename()) }
sub get_report_url { $_[0]->{'report-url'} }
sub set_report_url { $_[0]->{'report-url'} = $_[1] }
sub get_should_skip_report { $_[0]->{'skip-report'} }
sub is_narrow { $_[0]->get_filename() =~ /^\d\dn-/ }
sub get_type { $_[0]->{'type'} }

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

  if (defined $self->{rating3}) {
    return $self->{rating3};
  }

  if (defined $self->{rating2}) {
    if ($self->{rating2} <= 3) {
      return 1;
    } elsif ($self->{rating2} < 4) {
      return 2;
    } else {
      return 3;
    }
  }

  if (defined $self->{rating}) {
    if ($self->{rating} <= 45) {
      return 2;
    } else {
      return 3;
    }
  }

  return 3;
}


sub make_best_of_html {
    my @images = @_;

    @images = Scramble::Misc::dedup(@images);
    @images = sort { Scramble::Image::cmp($a, $b) } @images;
    if (@images > 10) {
        @images = @images[0..9];
    }

    return join("<p>", map { $_->get_html() } @images);
}

sub get_enlarged_html_url {
    my $self = shift;

    return undef unless defined $self->get_enlarged_filename();

    return "../../g/" . $self->get_enl_html_filename();
}

sub get_enlarged_img_url {
    my $self = shift;

    return sprintf("../../$g_pics_dir/%s/%s",
                   $self->get_subdirectory,
                   $self->get_enlarged_filename());
}

sub get_title_html { 
    my $self = shift;

    # have to calculate lazily b/c of circular dependencies with Scramble::Location

    if (! $self->{'title-html'}) {
	$self->{'title-html'} = Scramble::Misc::htmlify($self->get_title());
    }

    return $self->{'title-html'};
}

sub get_map_reference {
    my $self = shift;

    return { 'name' => $self->get_title(),
	     'URL' => $self->get_url(),
	     'id' => 'routeMap', # used by Scramble::Reference
	     'type' => ($self->{'noroute'} 
			? "Online map"
			: "Online map with route drawn on it"),
	 };
}

sub get_img_tag {
    my $self = shift;
    my (%options) = @_;
    
    my $enlarged = $options{'enlarged'};
    my $border = (! $enlarged && $self->get_enlarged_filename()) ? 2 : 0;
    return sprintf(qq(<img %s src="%s" alt="Image of %s" border="$border" hspace="1" vspace="1">),
                   (exists $options{'image-attributes'} ? $options{'image-attributes'} : ''),
                   $enlarged ? $self->get_enlarged_img_url() : $self->get_url(),
                   $self->get_title());
}

sub get_html {
    my $self = shift;
    my (%options) = @_;

    my $img_html = $self->get_img_tag(%options);
    if ($self->get_enlarged_html_url()) {
	$img_html = sprintf(qq(<a href="%s">$img_html</a>), $self->get_enlarged_html_url());

    }
    if ($options{'no-title'}) {
	return $img_html;
    }

    my $caption = $self->get_title_html();
    if ($self->get_report_url() && ! $options{'no-report-link'}) {
	$caption .= sprintf(qq( (from <a href="%s">this trip</a>)),
			    $self->get_report_url());

    }

    return Scramble::Misc::make_cell_html($img_html, $caption);
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

sub open_images_in_xml {
    my ($directory, $filename) = @_;

    my $xml = Scramble::XML::parse("$directory/$filename");
    $xml = Scramble::XML->new($xml);
    my $date = $xml->_get_required('date');
    my ($year, $month, $day) = Scramble::Time::parse_date($date);

    my $in_chronological_order = $xml->_get_optional('in-chronological-order');
    if (defined($in_chronological_order) && '' eq $in_chronological_order) {
	die "images.in-chronological-order is empty";
    }

    my @images;
    my $chronological_order = 0;
    foreach my $image_xml (@{ $xml->_get_optional("image") || [] }) {
        push @images, Scramble::Image->new_from_attrs({ 'date' => "$year/$month/$day",
                                                        'areas' => [ $xml->get_areas_from_xml() ],
                                                        'source-directory' => $directory,
                                                        'chronological-order' => $chronological_order++,
                                                        'in-chronological-order' => $in_chronological_order,
                                                        'trip-id' => $xml->_get_optional('trip-id'),
                                                        %$image_xml,
                                                    });
    }

    return @images;
}

sub open {
    my ($directory) = @_;

    if (! -d $directory) {
	die "images directory '$directory' does not exist";
    }

    my @images;
    foreach my $dir (glob "$directory/*") {
        next unless -d $dir;
        if (-e "$dir/images.xml") {
            push @images, open_images_in_xml($dir, "images.xml");
        } elsif (my @paths = glob "$dir/*.{jpg,JPG,jpeg,JPEG,gif,GIF}") {
            push @images, map { Scramble::Image->new_from_path($_) } @paths;
        } elsif ($dir !~ /CVS/) {
            print "No images in '$dir'\n";
        }
    }

    @images = sort { $a->cmp($b) } @images;

    $g_collection = Scramble::Collection->new('objects' => \@images);
}

my $g_image_index;
sub get_random_picture_html {
    my (%options) = @_;

    my @images = get_all_images_collection()->find('type' => 'picture');
    @images = grep { ($_->get_rating() <= $g_image_rating_threshold) } @images;
    if (! @images) {
	return '';
    }

    if (! defined $g_image_index) {
	$g_image_index = int(rand(scalar(@images)));
    }

    my $align;
    if (defined $options{'align'}) {
        $align = sprintf('align="%s"', $options{'align'}, 'right');
    } elsif (exists $options{'align'}) {
        $align = '';
    } else {
        $align = sprintf('align="%s"', 'right');
    }

    return $images[$g_image_index++ % @images]->get_html('no-title' => 1,
                                                         'image-attributes' => $align);
}

sub make_pictures_page {
    _make_images_page('type' => 'map', 
                      'columns' => 2);
    _make_images_page('type' => 'picture', 
                      'columns' => 2);
    _make_images_page('type' => 'picture', 
                      'columns' => 1, 
                      'filename' => "-with-paths",
                      'show-path' => 1, 
                      'images-per-page' => 99999);
    _make_images_page('type' => 'picture', 
                      'columns' => 1, 
                      'filename' => 'sorted-by-date',
                      'sort-by' => 'date',
                      'images-per-page' => 99999);
    make_enl_picture_pages();
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

    my $title_html = $self->get_title_html();
    if ($self->get_report_url()) {
        $title_html .= sprintf(qq( (from <a href="%s">this trip</a>)),
                               $self->get_report_url());
    }

    my $html = <<EOT;
<h1>$title_html</h1>
$image_html
EOT

    my $page_html
        = Scramble::Misc::make_1_column_page('title' => $self->get_title(),
                                             'date' => $self->get_date(),
                                             'html' => $html,
                                             'no-add-picture' => 1,
                                             'no-links-box' => 1);
    Scramble::Misc::create($output_filename, $page_html);
}

sub get_picture_html_filename {
    my ($i, %args) = @_;
    return sprintf("m/$args{type}s%s%s.html",
		   ($args{'filename'} ? $args{'filename'} : ''),
		   ($i == 0 ? "" : $i));
}
sub _make_images_page {
    my (%args) = @_;

    my ($type, $num_columns, $show_path, $n_pictures_per_page) = @args{qw(type columns show-path images-per-page)};

    $n_pictures_per_page = 10 unless defined $n_pictures_per_page;

    my $count = 0;
    my @images = Scramble::Image::get_all_images_collection()->find('type' => $type);
    if (! @images) {
	Scramble::Misc::create(get_picture_html_filename(0, %args),
			       Scramble::Misc::make_2_column_page("No Pictures", 
								  "I don't have any pictures yet", 
								  ));
	  return;
    }

    if ($args{'sort-by'}) {
        my $method = "get_" . $args{'sort-by'};
        @images = sort { $b->$method() cmp $a->$method() } @images;
    }

    my $n_pages = scalar(@images) / $n_pictures_per_page;
    for (my $i = 0; @images; ++$i) {
	my ($html1, $html2) = ('', '');
	foreach my $image (splice @images, 0, $n_pictures_per_page) {
	    my $html = sprintf("%s.%s<p>",
			       $image->get_html(),
			       ($show_path
                                ? sprintf("  Path (%s): %s/%s", $image->get_rating(), $image->get_subdirectory(), $image->get_filename())
                                : ''));
	    if ($type eq 'map' || 0 == $count++ % $num_columns) {
		$html1 .= $html;
	    } else {
		$html2 .= $html;
	    }
	}

        my $footer;
	if ($i > 0) {
	    $footer .= sprintf(qq(<A href="../../g/%s"><b>Previous&lt;</b></a>&nbsp;&nbsp;),
                               get_picture_html_filename($i-1, %args));
	}
        my @page_numbers = grep { $_ >= 0 && $_ < $n_pages } ($i - 10 .. $i + 10);
        foreach my $page_no (@page_numbers) {
            if ($page_no eq $i) {
                $footer .= "<b>&nbsp;" . ($i+1) . "&nbsp;</b> ";
            } else {
                $footer .= sprintf(qq(<A href="../../g/%s">%s</a> ),
                                   get_picture_html_filename($page_no, %args),
                                   $page_no + 1);
            }
        }
	if (@images) {
	    $footer .= sprintf(qq(&nbsp;&nbsp;<A href="../../g/%s"><b>&gt;Next</b></a>),
                               get_picture_html_filename($i+1, %args));
	}


	my $uctype = ucfirst($type);
	my $file = get_picture_html_filename($i, %args);
	Scramble::Misc::create($file,
			       Scramble::Misc::make_2_column_page("${uctype}s", 
								  $html1, 
								  $html2, 
								  'top-two-cell-row' => "$footer",
								  'bottom-two-cell-row' => "$footer",
								  'no-add-picture' => 1));
    }
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
    my $n_pictures_per_year = 25;
    my $n_per_date = 2;

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
	my @image_htmls;
        foreach my $image (@{ $pictures{$year}{images} }) {
	  push @image_htmls, Scramble::Misc::make_cell_html($image->get_html());
        }
	my $images_html = Scramble::Misc::render_cells_into_flow(\@image_htmls);

	my $title = "My Favorite Photos of $year";

	my $html = <<EOT;
<h1>$title</h1>
$header
$images_html
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
