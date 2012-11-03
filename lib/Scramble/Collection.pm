package Scramble::Collection;

use strict;

sub new {
    my $arg0 = shift;
    my (%args) = @_;

    my $self = {
		'objects' => [],
	       };
    bless($self, ref($arg0) || $arg0);

    $self->add(@{ $args{'objects'} }) if $args{'objects'};

    return $self;
}

sub get_all { @{ $_[0]->{'objects'} } }

sub add { 
    my $self = shift;
    my (@objs) = @_;

    foreach my $obj (@objs) {
	my $id = $obj->get_id();
	next if grep { $obj->equals($_) } @{ $self->{'id-cache'}{$id} || [] };
	push @{ $self->{'id-cache'}{$id} }, $obj;
        push @{ $self->{'objects'} }, $obj;
    }
}

sub _equals {
    my ($a, $b) = @_;

    if (! defined $a) {
	return ! defined $b;
    } elsif (! defined $b) {
	return 0;
    } elsif (ref $a) {
        return 0 == $a->cmp($b);
    } else {
	return $a eq $b;
    }
}
sub find { 
    my $self = shift;
    my (%args) = @_;

    my $id = delete $args{id};
    my @results = $id ? @{ $self->{'id-cache'}{$id} || [] } : $self->get_all();

    my $isa = delete $args{'isa'};
    if (defined $isa) {
	@results = grep { $_->isa($isa) } @results;
    }

    foreach my $key (keys %args) {
	my $method = "get_$key";
	$method =~ s/-/_/g;
	my @culled;
	foreach my $obj (@results) {
	    my @values = $obj->$method();
	    next unless @values;
	    next unless grep { _equals($_, $args{$key}) } @values;
	    push @culled, $obj;
	}
	@results = @culled;
    }

    return @results;
}

sub find_one {
    my $self = shift;
    my (%args) = @_;

    my @objs = $self->find(%args);
    @objs == 1 or die "Not exactly one match (@objs): " . Data::Dumper::Dumper(\%args);

    return $objs[0];
}

1;
