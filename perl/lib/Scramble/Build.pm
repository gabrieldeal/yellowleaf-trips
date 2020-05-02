package Scramble::Build;

use strict;

use File::Path ();
use IO::File ();
use Scramble::Build::Files ();
use Scramble::Build::Writer ();
use Scramble::Controller::GeekeryPage ();
use Scramble::Controller::PictureIndex ();
use Scramble::Controller::ListIndex ();
use Scramble::Controller::ListKml ();
use Scramble::Controller::ListPage ();
use Scramble::Controller::LocationPage ();
use Scramble::Controller::ReferenceIndex ();
use Scramble::Controller::StatsStdout ();
use Scramble::Controller::TripIndex ();
use Scramble::Controller::TripPrivateIndex ();
use Scramble::Controller::TripPage ();
use Scramble::Controller::TripRss ();
use Scramble::Logger ();
use Scramble::Misc ();
use Scramble::Model::Area ();
use Scramble::Model::File ();
use Scramble::Model::List ();
use Scramble::Model::Location ();
use Scramble::Model::Reference ();
use Scramble::Model::Trip ();
use Scramble::SpellCheck ();
use Scramble::Tests ();

sub new {
    my ($arg0, %args) = @_;

    my $self = {
        %args,
        writer => Scramble::Build::Writer->new($args{output_directory}),
    };
    bless($self, ref($arg0) || $arg0);

    return $self;
}

sub create {
    my $self = shift;

    srand($$ ^ time());
    Scramble::Logger::set_verbose($self->{verbose});
    Scramble::Model::Location::set_xml_src_directory($self->{xml_src_directory});
    Scramble::Model::Area::open($self->{xml_src_directory});
    Scramble::Model::Reference::open($self->{xml_src_directory});

    $self->create_directories;
    if ($self->build_specific_files) {
        return;
    }

    Scramble::Model::Trip::open_all($self->{files_src_directory}, $self->{xml_src_directory});
    Scramble::Model::List::open(glob("$self->{xml_src_directory}/lists/*.xml"));

    $self->should('spell') && Scramble::SpellCheck::check_spelling("$self->{xml_src_directory}/dictionary");
    $self->should('htaccess') && $self->make_htaccess();
    $self->should('javascript') && $self->make_javascript();
    $self->should('template') && $self->make_templates();
    $self->should('copy-files') && $self->copy_and_process_files();
    $self->should('kml') && $self->copy_kml();
    $self->should('trip-index') && Scramble::Controller::TripPrivateIndex->new->create($self->{writer});
    $self->should('trip-index') && Scramble::Controller::TripIndex::create_all($self->{writer}); # Includes home.html
    $self->should('link') && Scramble::Controller::ReferenceIndex::create($self->{writer});
    $self->should('list') && Scramble::Controller::ListIndex::create($self->{writer});
    $self->should('list') && Scramble::Controller::ListKml::create_all($self->{writer});
    $self->should('list') && Scramble::Controller::ListPage::create_all($self->{writer});
    $self->should('trip') && Scramble::Controller::TripPage::create_all($self->{writer});
    $self->should('rss') && Scramble::Controller::TripRss::create($self->{writer});
    $self->should('geekery') && Scramble::Controller::GeekeryPage::create($self->{writer});
    $self->should('picture-by-year') && Scramble::Controller::PictureIndex::create_all($self->{writer}); # Favorites
    $self->should('location') && Scramble::Controller::LocationPage::create_all($self->{writer});
    $self->should('short-trips') && Scramble::Controller::StatsStdout::display_short_trips();
    $self->should('party-stats') && Scramble::Controller::StatsStdout::display_party_stats();
    $self->should('test') && Scramble::Tests->new(output_dir => $self->{output_directory})->run;
}

sub should {
    my $self = shift;
    my ($page_type) = @_;

    return 0 if @{ $self->{file} } && ! @{ $self->{action} };
    return 0 if grep { $page_type eq $_ || "${page_type}s" eq $_ } @{ $self->{skip} };

    return 1 if ! @{ $self->{action} };
    return scalar(grep { $page_type eq $_ || "${page_type}s" eq $_ } @{ $self->{action} });
}

sub convert {
    my $self = shift;

    die "This code is stale";

    my @files = @{ $self->{file} } || glob("$self->{xml_src_directory}/locations/*.xml");
    Scramble::Converter::convert_locations($self->{xml_src_directory}, @files);
    @files = Scramble::Converter::convert_trips($self->{xml_src_directory}, @files);

    exit 0;
}

sub create_directories {
    my $self = shift;

    my @subdirs = qw(
        a
        enl
        js
        kml
        l
        li
        m
        r
    );
    my @paths = map { "$self->{output_directory}/g/$_" } @subdirs;

    File::Path::mkpath(\@paths, 0, 0755);
}

sub build_specific_files {
    my $self = shift;

    foreach my $file (@{ $self->{file} }) {
        if ($file =~ m{/trips/}) {
            my $trip = Scramble::Model::Trip::open_specific($file,
                                                            $self->{files_src_directory});
            $self->should('copy-files') && $self->copy_and_process_files();
            my $page = Scramble::Controller::TripPage->new($trip);
            $page->create($self->{writer});
        } else {
            # This does not work well because locations rely on
            # opening all trips to know which locations have been
            # visited.
            foreach my $location (Scramble::Model::Location::open_specific($file)) {
                my $page = Scramble::Controller::LocationPage->new($location);
                $page->create($self->{writer});
            }
        }
    }

    return scalar(@{ $self->{file} });
}

sub make_templates {
    my $self = shift;

    $self->make_html_file("$self->{templates_directory}/misc/kloke.html",
                          "Kloke's Cascade winter climbs",
                          'no-insert-links' => 1,
                          'enable-embedded-google-map' => 1,
                          'no-add-picture' => 1);
    $self->make_html_file("$self->{templates_directory}/misc/sfox.html",
                          "Steve Fox's winter scrambles",
                          'no-insert-links' => 1,
                          'no-add-picture' => 1);
    $self->make_html_file("$self->{templates_directory}/misc/missing.html",
                          "Missing Page",
                          'no-insert-links' => 1,
                          'no-add-picture' => 1);
}

sub copy_kml {
    my $self = shift;

    my $command = sprintf("cp %s/*.kml %s/g/kml/",
                          $self->{kml_directory},
                          $self->{output_directory});
    system($command);
    if ($?) {
        die "Error running $command: $!, $?";
    }
}

sub copy_and_process_files {
    my $self = shift;

    my @files = Scramble::Model::File::get_all;

    my $files = Scramble::Build::Files->new(files => \@files,
                                            code_dir => $self->{code_directory},
                                            output_dir => "$self->{output_directory}/pics");
    $files->build;
}

sub make_javascript {
    my $self = shift;

    my $target = $ENV{NODE_ENV} eq 'development' ? 'build-dev' : 'build';

    system("cd javascript && npm install && npm run $target");
    if ($?) {
        die "Error running webpack";
    }

    my $command = sprintf("cp %s/* %s/g/js/",
                          $self->{javascript_directory},
                          $self->{output_directory});
    print "$command\n";
    system($command);
    if ($?) {
        die "Error running $command: $!, $?";
    }
}

sub make_htaccess {
    my $self = shift;

    # Not r or li -- they have index.html files.
    foreach my $dir (qw(m l a)) {
        $self->{writer}->create("$dir/.htaccess", <<EOT);
Redirect /scramble/g/$dir/index.html http://$self->{site_root}/g/m/missing.html
EOT
    }

  $self->{writer}->create(".htaccess", <<EOT);
ErrorDocument 404 /scramble/g/m/missing.html
Redirect /scramble/g/index.html http://$self->{site_root}/g/m/missing.html
EOT

  # cheating here
  $self->{writer}->create("../.htaccess", <<EOT);
ErrorDocument 404 /scramble/g/m/home.html
Redirect /scramble/index.html http://$self->{site_root}/g/m/missing.html
EOT
}

sub make_template_html {
    my $self = shift;
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
    my $self = shift;
    my ($filename, $title, %options) = @_;

    if (! -e $filename) {
        die "Missing $filename";
    }

    my $html = $self->make_template_html($filename, %options);

    my ($ofile) = ($filename =~ m,/([^/]+)$,);

    $self->{writer}->create("m/$ofile",
                            Scramble::Template::page_html(title => $title,
                                                          'include-header' => 1,
                                                          %options,
                                                          html => $html));
}

1;
