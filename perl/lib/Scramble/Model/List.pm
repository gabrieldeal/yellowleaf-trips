package Scramble::Model::List;

use strict;

use Scramble::Misc;
use Scramble::Model;
use Scramble::Logger;

# FIXME: Convert this to a class.

my @g_lists;
sub get_all_lists {
    return @g_lists;
}

sub get_sortby {
    my ($list_xml) = @_;

    return $list_xml->{'sortby'};
}

sub get_id {
    my ($list_xml, $sortby) = @_;

    defined $list_xml->{'id'} or die "Missing ID";
    my $id = $list_xml->{'id'};
    if (defined $sortby) {
	$id .= $sortby;
    } elsif (exists $list_xml->{'sortedby'}) {
	$id .= $list_xml->{'sortedby'};
    }

    return $id;
}

sub location_equals {
    my ($a, $b) = @_;

    return ($a->{'name'} eq $b->{'name'}
            && $a->{'quad'} eq $b->{'quad'}
            && (! $a->{'county'}
                || $a->{'county'} eq $b->{'county'}));
}

sub new_sorted_list {
    my ($old_list, $sortby) = @_;

    my %new_list = %$old_list;
    $new_list{'location'} = [ map { { %$_ } } @{ $old_list->{'location'} } ];
    $new_list{'location'} = [ sort({ sort_list($sortby, $a, $b) } @{ $new_list{'location'} }) ];
    $new_list{'sortedby'} = $sortby;

    # Now that it is sorted, remove duplicate locations from the list:
    for (my $i = 0; $i + 1 < @{ $new_list{'location'} }; ++$i) {
        my $cur = $new_list{'location'}[$i];
        my $next = $new_list{'location'}[$i+1];
        if (location_equals($cur, $next)) {
            splice(@{ $new_list{'location'} }, $i + 1, 1);
            $i--;
        }
    }

    my $count = 1;
    map { $_->{'order'} = $count++ } @{ $new_list{'location'} };

    return \%new_list;
}

sub open {
    my (@paths) = @_;
    
    @g_lists = Scramble::Model::open_documents(@paths);
    @g_lists or die "No lists";

    for (my $i = 0; $i < @g_lists; ++$i) {
	Scramble::Logger::verbose "Processing $g_lists[$i]{'name'}\n";
	next unless exists $g_lists[$i]{'sortby'};
	
	my $sortby = get_sortby($g_lists[$i]);
	my $new_list = new_sorted_list($g_lists[$i], $sortby);
	splice(@g_lists, $i, 1, $new_list);
    }
    for (my $i = 0; $i < @g_lists; ++$i) {
        $g_lists[$i]{'internal-URL'} = sprintf("../%s",
                                               get_list_path($g_lists[$i]));
	next if exists $g_lists[$i]{'URL'};
	$g_lists[$i]{'URL'} = $g_lists[$i]{'internal-URL'};
    }
}

sub sort_list {
    my ($by, $l1, $l2) = @_;

    if ($by eq 'elevation') {
        my %e1 = Scramble::Misc::get_elevation_details(get_elevation($l1));
        my %e2 = Scramble::Misc::get_elevation_details(get_elevation($l2));
	return $e2{feet} <=> $e1{feet};
    } elsif ($by eq 'MVD') {
        return $l2->{'MVD'} <=> $l1->{'MVD'};
    } else {
	die "Not implemented '$by'";
    }
}

sub get_location_object {
    my ($list_location) = @_;

    my $name = $list_location->{'name'};
    return undef unless $name;

    if (! exists $list_location->{'object'}) {
	$list_location->{'object'} =  eval { 
	    Scramble::Model::Location::find_location('name' => $name,
                                                     'quad' => $list_location->{'quad'},
                                                     'include-unvisited' => 1);
	  };
    }
    return $list_location->{'object'};
}

sub get_is_unofficial_name {
    my ($list_location) = @_;

    my $location = get_location_object($list_location);
    if ($location) {
	return $location->get_is_unofficial_name();
    }

    return $list_location->{'unofficial-name'};
}

sub get_elevation {
    my ($list_location) = @_;

    local $Data::Dumper::Maxdepth = 2;

    my $location = get_location_object($list_location);
    if ($location) {
	return $location->get_elevation() || die "No elevation: " . Data::Dumper::Dumper($list_location);
    }

    return $list_location->{'elevation'} || die "No elevation: " . Data::Dumper::Dumper($list_location);
}

sub get_aka_names {
    my ($list_location) = @_;
    
    my $location = get_location_object($list_location);
    if ($location) {
	return join(", ", $location->get_aka_names());
    }

    return $list_location->{'AKA'};
}

sub get_list_path {
    my ($list_xml, $sortby) = @_;

    return sprintf("li/%s.html",
		   Scramble::Misc::make_location_into_path(get_id($list_xml, $sortby)));
}

sub make_list_link {
    my ($list_xml) = @_;

    return sprintf(qq(<a href="%s">%s</a>),
                   $list_xml->{'URL'},
		   $list_xml->{'name'});
}

sub get_kml_path {
    my ($list_xml) = @_;

    my $list_id = Scramble::Misc::make_location_into_path(Scramble::Model::List::get_id($list_xml, ''));

    return "li/$list_id.kml"
}

sub get_kml_url {
    my ($list_xml) = @_;

    my $path = get_kml_path($list_xml);

    return "../$path";
}

1;
