package Scramble::Build;

use strict;

use Date::Manip ();
use File::Find ();
use File::Path ();
use IO::File ();
use Scramble::Build::Files ();
use Scramble::Controller::GeekeryPage ();
use Scramble::Controller::ImageIndex ();
use Scramble::Controller::ListIndex ();
use Scramble::Controller::ListKml ();
use Scramble::Controller::ListPage ();
use Scramble::Controller::LocationPage ();
use Scramble::Controller::ReferenceIndex ();
use Scramble::Controller::StatsStdout ();
use Scramble::Controller::TripIndex ();
use Scramble::Controller::TripPage ();
use Scramble::Controller::TripRss ();
use Scramble::Logger ();
use Scramble::Misc ();
use Scramble::Model::Area ();
use Scramble::Model::Image ();
use Scramble::Model::List ();
use Scramble::Model::Location ();
use Scramble::Model::Reference ();
use Scramble::Model::Trip ();
use Scramble::SpellCheck ();
use Scramble::Tests ();

my $gRoot = "yellowleaf.org/scramble";

my @g_options = qw(
    code-directory=s
    xml-src-directory=s
    timezone=s
    verbose
    action=s@
    skip=s@
    file=s@
    files-src-directory=s
    kml-directory=s
    templates-directory=s
    javascript-directory=s
    output-directory=s
    help
    );
my %g_options = (
    "file" => [],
    "action" => [],
    "skip" => [],
    "timezone" => "PDT",
    "kml-directory" => "kml",
    "templates-directory" => "view",
    "javascript-directory" => "javascript/dist",
    "output-directory" => "html",
    );
my @required = qw(
    code-directory
    files-src-directory
    output-directory
    javascript-directory
    templates-directory
    );

sub get_options {
    %g_options = Scramble::Misc::get_options(defaults => \%g_options,
                                             options => \@g_options,
                                             required => \@required);

    Scramble::Misc::set_output_directory($g_options{'output-directory'});
    Scramble::Logger::set_verbose($g_options{'verbose'});
}

sub create {
    srand($$ ^ time());
    get_options();

    my $paths = [
        "$g_options{'output-directory'}/g/li",
        "$g_options{'output-directory'}/g/a",
        "$g_options{'output-directory'}/g/js",
        "$g_options{'output-directory'}/g/r",
        "$g_options{'output-directory'}/g/l",
        "$g_options{'output-directory'}/g/enl",
        "$g_options{'output-directory'}/g/kml",
        "$g_options{'output-directory'}/g/m",
    ];
    File::Path::mkpath($paths, 0, 0755);

    should('htaccess') && make_htaccess();
    should('javascript') && make_javascript();
    should('template') && make_templates();

    Scramble::Model::Location::set_xml_src_directory($g_options{'xml-src-directory'});
    Scramble::Model::Area::open($g_options{'xml-src-directory'});
    Scramble::Model::Reference::open($g_options{'xml-src-directory'});

    # if (0 && should('convert')) {
    #     my @files = @{ $g_options{'file'} } || glob("$g_options{'xml-src-directory'}/locations/*.xml");
    #     Scramble::Converter::convert_locations($g_options{'xml-src-directory'}, @files);
    #     @files = ...
    #     Scramble::Converter::convert_trips($g_options{'xml-src-directory'}, @files);
    #     exit 0;
    # }

    if (! @{ $g_options{'file'} }) {
        Scramble::Model::Trip::open_all($g_options{'files-src-directory'},
                                        $g_options{'xml-src-directory'});
    } else {
	foreach my $file (@{ $g_options{'file'} }) {
            if ($file =~ m{/trips/}) {
                my $trip = Scramble::Model::Trip::open_specific($file,
                                                                $g_options{'files-src-directory'});
                should('copy-images') && copy_and_process_files();
                my $page = Scramble::Controller::TripPage->new($trip);
                $page->create;
            } else {
                foreach my $location (Scramble::Model::Location::open_specific($file)) {
                    my $page = Scramble::Controller::LocationPage->new($location);
                    $page->create;
                }
            }
        }
    }
    should('spell') && Scramble::SpellCheck::check_spelling("$g_options{'xml-src-directory'}/dictionary");
    if (@{ $g_options{'file'} }) {
        return 0;
    }

    Scramble::Model::List::open(glob("$g_options{'xml-src-directory'}/lists/*.xml"));

    should('copy-images') && copy_and_process_files();
    should('kml') && copy_kml();
    should('trip-index') && Scramble::Controller::TripIndex::create_all(); # This includes home.html
    should('link') && Scramble::Controller::ReferenceIndex::create();
    should('list') && Scramble::Controller::ListIndex::create();
    should('list') && Scramble::Controller::ListKml::create_all();
    should('list') && Scramble::Controller::ListPage::create_all();
    should('trip') && Scramble::Controller::TripPage::create_all();
    should('rss') && Scramble::Controller::TripRss::create();
    should('geekery') && Scramble::Controller::GeekeryPage::create();
    should('picture-by-year') && Scramble::Controller::ImageIndex::create_all(); # Favorites
    should('location') && Scramble::Controller::LocationPage::create_all();
    should('short-trips') && Scramble::Controller::StatsStdout::display_short_trips();
    should('party-stats') && Scramble::Controller::StatsStdout::display_party_stats();
    should('test') && Scramble::Tests::run();

    return 0;
}

sub should {
    my ($page_type) = @_;

    return 0 if @{ $g_options{'file'} } && ! @{ $g_options{'action'} };
    return 0 if grep { $page_type eq $_ || "${page_type}s" eq $_ } @{ $g_options{'skip'} };

    return 1 if ! @{ $g_options{'action'} };
    return scalar(grep { $page_type eq $_ || "${page_type}s" eq $_ } @{ $g_options{'action'} });
}

sub make_templates {
    make_html_file("$g_options{'templates-directory'}/misc/kloke.html",
                   "Kloke's Cascade winter climbs",
                   'no-insert-links' => 1,
                   'enable-embedded-google-map' => 1,
                   'no-add-picture' => 1);
    make_html_file("$g_options{'templates-directory'}/misc/sfox.html",
                   "Steve Fox's winter scrambles",
                   'no-insert-links' => 1,
                   'no-add-picture' => 1);
    make_html_file("$g_options{'templates-directory'}/misc/missing.html",
                   "Missing Page",
                   'no-insert-links' => 1,
                   'no-add-picture' => 1);
}

sub copy_kml {
    my $command = sprintf("cp %s/*.kml %s/g/kml/",
                          $g_options{'kml-directory'},
                          $g_options{'output-directory'});
    system($command);
    if ($?) {
        die "Error running $command: $!, $?";
    }
}

sub copy_and_process_files {
    my @images = Scramble::Model::Image::get_all_images_collection()->get_all;

    my $files = Scramble::Build::Files->new(images => \@images,
                                            code_dir => $g_options{'code-directory'},
                                            output_dir => $g_options{'output-directory'});
    $files->build;
}

sub make_javascript {
    my $target = $ENV{'NODE_ENV'} eq 'development' ? 'build-dev' : 'build';

    system("cd javascript && npm install && npm run $target");
    if ($?) {
        die "Error running webpack";
    }

    my $command = sprintf("cp %s/* %s/g/js/",
                          $g_options{'javascript-directory'},
                          $g_options{'output-directory'});
    print "$command\n";
    system($command);
    if ($?) {
        die "Error running $command: $!, $?";
    }
}

sub make_htaccess {
    # Not r or li -- they have index.html files.
    foreach my $dir (qw(m l a)) {
        Scramble::Misc::create("$dir/.htaccess", <<EOT);
Redirect /scramble/g/$dir/index.html http://$gRoot/g/m/missing.html
EOT
    }

  Scramble::Misc::create(".htaccess", <<EOT);
ErrorDocument 404 /scramble/g/m/missing.html
Redirect /scramble/g/index.html http://$gRoot/g/m/missing.html
EOT

  # cheating here
  Scramble::Misc::create("../.htaccess", <<EOT);
ErrorDocument 404 /scramble/g/m/home.html
Redirect /scramble/index.html http://$gRoot/g/m/missing.html
EOT
}

sub make_template_html {
    my ($filename, %options) = @_;

    my $fh = IO::File->new($filename, 'r')
	or die "Unable to open '$filename': $!";
    my $html = join('', <$fh>);
    if (! $options{'no-insert-links'}) {
        Scramble::Misc::insert_links($html);
    }
    $html .= delete $options{'after-file-contents'} if exists $options{'after-file-contents'};

    return $html;
}

sub make_html_file {
    my ($filename, $title, %options) = @_;

    if (! -e $filename) {
        die "Missing $filename";
    }

    my $html = make_template_html($filename, %options);

    my ($ofile) = ($filename =~ m,/([^/]+)$,);

    Scramble::Misc::create("m/$ofile",
                           Scramble::Template::page_html(title => $title,
                                                         'include-header' => 1,
                                                         %options,
                                                         html => $html));
}

1;
