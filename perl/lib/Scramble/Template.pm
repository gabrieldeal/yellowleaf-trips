package Scramble::Template;

use strict;

use HTML::Template ();

my @g_navbar_links = (
    {'url' => qq(../../g/m/home.html),
         'text' => 'Trips',
    },
    { url => qq(../../g/m/pcurrent.html),
      'text' => 'Favorite photos',
    },
    { 'url' => qq(../../g/li/index.html),
          'text' => 'Peak lists',
    },
    { 'url' => qq(../../g/m/references.html),
          'text' => 'References',
    },
    { 'url' => qq(mailto:scramble\@yellowleaf.org),
          'text' => 'Contact',
    },
    );

sub html {
    my ($name, $params) = @_;

    my $template = Scramble::Template::create($name);
    $template->param(%$params);

    return $template->output();
}

sub create {
    my ($name) = @_;

    my $filename = "view/$name.html";

    return HTML::Template->new(filename => $filename,
                               default_escape => 'html');
}

sub common_params {
    my %args = @_;

    my $year = (localtime)[5] + 1900;
    my $copyright = $args{copyright} || 'Gabriel Deal';

    return (
        copyright_year => $year,
        copyright_holder => $copyright,
        deploy_refresh => $$, # Cheap way to invalidate browser cache.
        navbar_links => \@g_navbar_links,
        );
}

1;
