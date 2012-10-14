package Scramble::Collection;

use strict;

sub new {
    my $arg0 = shift;
    my (%args) = @_;

    my @objects;
    if ($args{'objects'}) {
	push @objects, @{ $args{'objects'} };
    }

    my $self = {'objects' => \@objects,
	    };

    return bless($self, ref($arg0) || $arg0);
}

sub get_all { @{ $_[0]->{'objects'} } }

sub add { 
    my $self = shift;
    my (@objs) = @_;

    foreach my $obj (@objs) {
        push @{ $self->{'objects'} }, $obj
            unless grep { $obj->equals($_) } $self->get_all();
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

    my $isa = delete $args{'isa'};
    my @results = $self->get_all();
    foreach my $key (keys %args) {
	my $method = "get_$key";
	$method =~ s/-/_/g;
	my @culled;
	foreach my $obj (@results) {
	    if (defined $isa && ! $obj->isa($isa)) {
		next;
	    }
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
