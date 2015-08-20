package Scramble::Converter::Report;

use strict;

use XML::Generator ();

sub new {
    my ($arg0, $report) = @_;

    my $self = {
	report => $report,
	xml_generator => XML::Generator->new(':pretty')
    };

    return bless $self, ref($arg0) || $arg0;
}

sub xg { $_[0]->{xml_generator} }
sub r { $_[0]->{report} }

sub convert {
    my $self = shift;

    return $self->xg->trip($self->make_trip_attributes());
}

sub make_trip_attributes {
    my $self = shift;

    my $r = $self->r();
    return {
	id => $r->get_trip_id(),
	type => $r->get_type(),
	name => $r->get_name(),
	state => $r->get_state(),
	should_show => $r->should_show(),
    };
}


1;
