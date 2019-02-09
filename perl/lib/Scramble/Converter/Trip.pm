package Scramble::Converter::Trip;

use strict;

use XML::Generator ();

sub new {
    my ($arg0) = @_;

    my $self = {
	xml_generator => XML::Generator->new(escape => 'always',
					     conformance => 'strict',
					     pretty => 4)
    };

    return bless $self, ref($arg0) || $arg0;
}

sub xg { $_[0]->{xml_generator} }
sub r { $_[0]->{trip} }

sub convert {
    my $self = shift;
    my ($trip) = @_;

    $self->{trip} = $trip;
    my $xg = $self->xg();

    my @tags;
    push @tags, $xg->description({}, $trip->get_route()) if $trip->get_route();
    push @tags, $xg->private({}, $trip->_get_optional_content('private')) if $trip->_get_optional_content('private');
    push @tags, $xg->comments({}, $trip->_get_optional_content('comments')) if  $trip->_get_optional_content('comments');
    push @tags, $self->make_named_array_tag('locations', ['location', 'not']);
    push @tags, $self->make_named_array_tag('references', 'reference');
    push @tags, $self->make_named_array_tag('areas', 'area');
    push @tags, $self->make_named_array_tag('rock-routes', 'rock-route');
    push @tags, $self->make_named_array_tag('maps', 'map');
    push @tags, $self->make_named_array_tag('round-trip-distances', 'distance');
    push @tags, $self->make_party_tag();
    if ($trip->_get_optional('times', 'miles')) {
	my $tag = "round-trip-distances";
	push @tags, $xg->$tag({}, $xg->distance({type=>'foot', miles=>$trip->_get_optional('times', 'miles')}));
    }
    push @tags, $self->make_waypoints_tag();
    push @tags, $self->make_files_tag();

    return $xg->trip($self->make_trip_attributes(), @tags);
}


sub make_files_tag {
    my $self = shift;

    my $xg = $self->xg();
    my $r = $self->r();

    my @pictures = Scramble::Model::File::get_pictures_collection->find('trip-id' => $r->get_trip_id(),
                                                                        'date' => $r->get_start_date());

    return () unless @pictures;

    my @files;
    my $in_chronological_order = undef;
    foreach my $file (@files) {
	$in_chronological_order = $file->in_chronological_order() unless defined $in_chronological_order;
	push @files, $xg->file({ type => $file->get_type(),
				 description => $file->get_description(),
				 'thumbnail-filename' => $file->get_filename(),
				 'large-filename' => $file->get_enlarged_filename(),
				 rating => $file->get_rating(),
				 owner => $file->{photographer},
				 'capture-timestamp' => $file->{'capture-timestamp'}
			     });
    }

    my %file_attrs = ( 'in-chronological-order' => $in_chronological_order );
    return $xg->files(\%file_attrs, @files);
}


sub make_waypoints_tag {
    my $self = shift;

    my $r = $self->r();

    return () unless $r->get_waypoints();
    return $self->make_waypoints1_tag() if ref($r->get_waypoints()) =~ /Scramble::Model::Waypoints\b/;
    return $self->make_waypoints2_tag();
}
sub epoch_to_time {
    my ($epoch) = @_;

    my ($sec, $min, $hour, $mday, $mon, $year) = localtime($epoch);
    $year += 1900;
    $mon++;

    return sprintf("%d/%02d/%02d %02d:%02d", $year, $mon, $mday, $hour, $min);
}
sub make_waypoints1_tag {
    my $self = shift;

    my $xg = $self->xg();
    my $r = $self->r();

    my @waypoint_tags;
    my ($last_end_location, $last_end_altimeter);
    my $current_time = 0;
    foreach my $waypoint ($r->get_waypoints()->get_waypoints()) {
	if ($waypoint->get_start_location()) {
	    my $start_time = $waypoint->get_start_time();
	    if (! defined $start_time && ($waypoint->_get_optional('hours') || $waypoint->_get_optional('minutes'))) {
		$start_time = epoch_to_time($current_time);
	    }

	    push @waypoint_tags, $xg->waypoint({ type => $waypoint->get_type(),
						 'location-description' => $waypoint->get_start_location() || $last_end_location,
						 elevation => $waypoint->get_start_altimeter() || $last_end_altimeter,
						 time => $start_time
					     });
	}

	my $end_time = $waypoint->get_end_time();
	if (! defined $end_time && ($waypoint->_get_optional('hours') || $waypoint->_get_optional('minutes'))) {
	    $current_time += 60 * 60 * ($waypoint->_get_optional('hours') || 0) + 60 * ($waypoint->_get_optional('minutes') || 0);
	    $end_time = epoch_to_time($current_time);
	}
	my $last_end_location = $waypoint->get_end_location();
	my $last_end_altimeter = $waypoint->get_end_altimeter();
	push @waypoint_tags, $xg->waypoint({ type => 'break',
					     'location-description' => $waypoint->get_end_location(),
					     elevation => $waypoint->get_end_altimeter(),
					     time => $end_time
					 });
    }
    

    my %waypoint_attrs;
    return $xg->waypoints(\%waypoint_attrs, @waypoint_tags);
}

sub make_waypoints2_tag {
    my $self = shift;

    my $xg = $self->xg();
    my $r = $self->r();

    return () unless $r->get_waypoints()->get_waypoints() or $r->get_waypoints()->_get_optional('elevation-gain');

    my @waypoint_tags;
    foreach my $waypoint ($r->get_waypoints()->get_waypoints()) {
	push @waypoint_tags, $xg->waypoint({ type => $waypoint->get_type(),
					     'location-description' => $waypoint->get_location(),
					     elevation => $waypoint->get_elevation(),
					     time => $waypoint->get_time(),
					 });
    }

    my %waypoint_attrs = ( 'elevation-gain' => $r->get_waypoints()->_get_optional('elevation-gain') );
    return $xg->waypoints(\%waypoint_attrs, @waypoint_tags);
}

sub make_trip_attributes {
    my $self = shift;

    my $r = $self->r();

    my $filename = File::Basename::basename($r->{path});
    $filename =~ s/\.xml$//;

    return {
	id => $r->get_trip_id(),
	'start-date' => $r->get_start_date(),
	'end-date' => $r->get_end_date(),
	type => $r->get_type(),
	name => $r->get_name(),
	filename => $filename,
	state => $r->get_state(),
	'should-not-show' => ! $r->should_show() ? 1 : undef,
    };
}

sub make_party_tag {
    my $self = shift;

    my $r = $self->r();
    my $xg = $self->xg();

    my $party = $r->_get_optional_content('party');
    return () unless $party;

    my @tags = map { $xg->member($_) } @{ $party->{member} || [] };
    push @tags, $party->{content} if $party->{content};

    my %attrs = ( size => $party->{size} );
    return $xg->party(\%attrs, @tags);
}

sub make_named_array_tag {
    my $self = shift;
    my ($name, $sub_names) = @_;

    my $r = $self->r();
    my $xg = $self->xg();

    my @tags;
    foreach my $sub_name (ref $sub_names ? @$sub_names : ($sub_names)) {
	foreach my $tag (@{ $r->_get_optional($name, $sub_name) || [] }) {
	    push @tags, $xg->$sub_name($tag);
	}
    }

    return () unless @tags;

    return $xg->$name({}, @tags);
}

1;
