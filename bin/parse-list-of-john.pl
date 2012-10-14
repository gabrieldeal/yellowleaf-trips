use strict;

use HTML::TreeBuilder;
use URI::WithBase ();
use LWP::Simple ();
use Data::Dumper;

exit(main());

sub main {
  my $state_page_url = "http://listsofjohn.com/PeakStats/countystats.php?sort=&State=WA";
  my $state_page = get_tree($state_page_url);

  my @county_urls;
  my @county_trs = $state_page->find("tr");
  shift @county_trs; # the <th> element
  foreach my $county_tr (@county_trs) {
    my (@a) = $county_tr->find('a');
    next if @a == 0;
    (scalar(@a) == 1) or die sprintf("Too many (%d) 'a' tag in %s", scalar(@a), $county_tr->dump());
    my $county_page_url = $a[0]->attr('href');
    my $uri = URI::WithBase->new($county_page_url, $state_page_url);
    push @county_urls, $uri->abs();
  }

  my @county_summit_urls;
  foreach my $county_url (@county_urls) {
    my $tree = get_tree($county_url);
    my @link = $tree->look_down(sub {
				  $_[0]->tag() eq 'a'
				    && grep({ $_ =~ /Click for .* County Summits List/ } $_[0]->content_list)
				  });
    @link == 1 or die $tree->dump();
    my $uri = URI::WithBase->new($link[0]->attr('href'), $county_url);
    push @county_summit_urls, $uri->abs();

  }

  my @peak_urls;
  foreach my $county_summit_url (@county_summit_urls) {
    my $tree = get_tree($county_summit_url);
    my @links = $tree->look_down(sub {
				   $_[0]->tag() eq 'a'
				     && $_[0]->attr('href') =~ /Climbers\.php/
				   });
    foreach my $link (@links) {
      my $uri = URI::WithBase->new($link->attr('href'), $county_summit_url);
      push @peak_urls, $uri->abs();
    }
  }

  my @fields = qw(Elevation
		  Counties
		  Quad
		  Coords
		  Rise
		 );
  my %peaks;
  foreach my $peak_url (@peak_urls) {
    my $tree = get_tree($peak_url);
    my @fonts = $tree->look_down(sub { $_[0]->tag() eq 'font' });
    shift @fonts; # Peak Statistics
    my $name_font = shift @fonts;
    my @b = $name_font->content_list();
    @b == 1 or die "too many b's: " . $name_font->dump();
    my @name = $b[0]->content_list();
    @name == 1 or die "too many names: " . Dumper(@name);

    my %fields;
    foreach my $font (@fonts) {
      my $continue = add_contents_to_map([ $font->content_list() ], \%fields);
      last unless $continue;
    }

    my $quad = $fields{'Quad:'}[0];
    $peaks{$name[0]}{$quad} = { name => $name[0],
				quad => $quad,
				elevation => numberify($fields{'Elevation:'}[0]),
				coordinates => parse_coords($fields{'Coords:'}[0]),
				prominence => numberify($fields{'Rise:'}[0]),
				counties => $fields{'Counties:'},
			      };
    print Dumper($peaks{$name[0]}{$quad});
  }
print Dumper(\%peaks);

  return 0;
}

sub add_contents_to_map {
  my ($contents, $output) = @_;

  my @text;
  foreach my $content (@$contents) {
    push @text, get_peak_field($content);
  }

  for (my $i = 1; $i < @text; ++$i) {
    next unless $text[$i] eq ':';

    splice(@text, $i, 1);
    $text[$i-1] .= ":";
  }

  my $key;
  for my $text (@text) {
    return 0 if $text eq 'Saddle:';
    if ($text =~ /:$/) {
      $key = $text;
      $output->{$key} = [];
    } elsif ($text ne '') {
      push @{ $output->{$key} }, $text;
    }
  }

  return 1;
}

sub get_peak_field {
  my ($content) = @_;

  if (! ref($content)) {
    $content =~ s/^\s*//;
    $content =~ s/\s*$//;

    my @colon;
    if ($content =~ s/^\s*:\s*//) {
      push @colon, ":";
    }
    if ($content eq 'and' or $content eq '&') {
      return @colon;
    }
    return (@colon, $content);
  }

  if ($content->tag() eq 'a') {
    if ($content->attr('title') eq 'Click for Definition') {
      return ();
    } else {
      return ($content->content_list());
    }
  }

  return ();
}

sub parse_coords {
  my ($text) = @_;

  my ($lon, $n, $lat, $w) = ($text =~ /^(\d+\.\d+).([NS]), (\d+\.\d+).([WE])$/);
  defined $lat or die "Unable to parse lat/lon '$text'";

  $lon = ($w eq 'W' ? -$lon : $lon);
  $lat = ($w eq 'S' ? -$lat : $lat);
  return { longitude => $lon,
	   latitude => $lat,
	 };
}

sub numberify {
  my ($text) = @_;

  $text =~ s/[^\d]*//g;

  return $text;
}


sub get_tree {
  my ($url) = @_;

  my $html = LWP::Simple::get($url);

  my $tree = HTML::TreeBuilder->new();
  $tree->parse($html);
  $tree->eof();

$|=1;
print ".";
select(undef, undef, undef, 0.25);

  return $tree;
}

