package Scramble::Controller::ReferenceIndex;

use strict;

use Scramble::Misc ();
use Scramble::Model::Reference ();
use Scramble::Controller::ReferenceFragment ();

sub create {
    my @references_param;
    my @references = values %{ Scramble::Model::Reference::get_all() };
    @references = sort { Scramble::Model::Reference::cmp_references($a, $b) } @references;
    foreach my $reference (@references) {
	next unless $reference->{'name'};
	next unless $reference->{'link'};
        my $name = Scramble::Model::Reference::get_reference_attr('name', $reference);
        my $type = Scramble::Controller::ReferenceFragment::get_type($reference);
        my $url = Scramble::Model::Reference::get_reference_attr('URL', $reference);

        push @references_param, {
            name => $name,
            type => $type,
            url => $url,
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
