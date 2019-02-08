package Scramble::Controller::ReferenceIndex;

use strict;

use Scramble::Misc ();
use Scramble::Model::Reference ();
use Scramble::Controller::ReferenceFragment ();

sub create {
    my ($writer) = @_;

    my @references_param;
    my @references = Scramble::Model::Reference::get_all();
    @references = sort { Scramble::Model::Reference::cmp($a, $b) } @references;
    foreach my $reference (@references) {
        next unless $reference->get_name();
        next unless $reference->should_link();

        my $type = Scramble::Controller::ReferenceFragment->new($reference)->get_type;

        push @references_param, {
            name => $reference->get_name(),
            type => $type,
            url => $reference->get_url(),
        };
    }

    my %params = (references => \@references_param);
    my $html = Scramble::Template::html('reference/index', \%params);

    $writer->create("m/references.html",
                    Scramble::Template::page_html(title => "References",
                                                  html => $html,
                                                  'include-header' => 1));
}

1;
