package Scramble::Controller::ReferenceIndex;

use strict;

use Scramble::Misc ();
use Scramble::Model::Reference ();
use Scramble::Controller::ReferenceFragment ();

sub create {
    my @references_param;
    my @references = Scramble::Model::Reference::get_all();
    @references = sort { Scramble::Model::Reference::cmp($a, $b) } @references;
    foreach my $reference (@references) {
        next unless $reference->get_name();
        next unless $reference->should_link();

        my $type = Scramble::Controller::ReferenceFragment::get_type($reference);

        push @references_param, {
            name => $reference->get_name(),
            type => $type,
            url => $reference->get_url(),
        };
    }

    my %params = (references => \@references_param);
    my $html = Scramble::Template::html('reference/index', \%params);

    Scramble::Misc::create("m/references.html",
                           Scramble::Misc::make_1_column_page(title => "References",
                                                              html => $html,
                                                              'include-header' => 1));
}

1;
