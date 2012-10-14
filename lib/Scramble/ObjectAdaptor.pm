package Scramble::ObjectAdaptor;

use strict;

our $AUTOLOAD;

sub new {
    my $arg0 = shift;
    my ($obj) = @_;

    return bless({ 'obj' => $obj }, ref($arg0) || $arg0);
}

sub set {
    my $self = shift;
    my ($method, $impl) = @_;

    $self->{'m'}{$method} = $impl;
    return $self;
}

sub AUTOLOAD { 
    my $self = shift;
    my (@args) = @_;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;
    return if $name eq 'DESTROY';
    if (exists $self->{'m'}{$name}) {
	return $self->{'m'}{$name}->($self->{'obj'}, @args);
    } else {
	return $self->{'obj'}->$name(@args);
    }
}

1;
