package Scramble::Controller::ReferenceFragment;

use strict;

# FIXME: Refactor this.

sub new {
    my ($arg0, $reference) = @_;

    my $self = {
        reference => $reference,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub params {
    my $self = shift;

    return {
        note_html => Scramble::Htmlify::insert_links($self->{reference}->get_note),
        name => $self->get_name,
        type => $self->get_type,
        url => $self->{reference}->get_url,
    };
}

sub short_params {
    my $self = shift;

    return {
        reference_name => $self->get_name,
        reference_url => $self->{reference}->get_url,
    };
}

sub get_name {
    my $self = shift;

    return $self->{reference}->get_page_name || $self->{reference}->get_name;
}

sub get_type {
    my $self = shift;

    my $type = $self->{reference}->get_type;
    if (!$type) {
        $type = $self->{reference}->get_name;
    }
    if ($self->{reference}->get_season) {
        $type = ucfirst($self->{reference}->get_season) . " $type";
    }

    return $type;
}

1;
