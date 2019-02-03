package Scramble::Controller::TripXml;

use strict;

use XML::Generator ();

my $xg = XML::Generator->new(escape => 'always',
                             conformance => 'strict',
                             pretty => 4);

# FIXME: Refactor to use XML::Generator. Move interactive code out.

sub prompt_yes_or_no {
    my ($prompt) = @_;
    while (1) {
        print "$prompt\ny/n (y)? ";
        my $answer = <STDIN>;
        chomp $answer;

        return 1 if lc($answer) eq 'y' || $answer eq '';
        return 0 if lc($answer) eq 'n';
    }
}

sub make_files_xml {
    my ($files, $date, $sections) = @_;

    my @file_xmls;
    foreach my $file (sort { $a->{timestamp} cmp $b->{timestamp} } @$files) {
        my %optional_attrs;
        if ($file->{caption} =~ /^(.+)\s+(from|over)\s+(.+)/) {
            my ($of, $term, $from) = ($1, $2, $3);
            $from = '' if $term eq 'over';
            my $question = "\n$file->{caption}\nSet the 'of' and 'from' attributes to the below? ('n' sets it to nothing)\nof: $of\nfrom: $from";
            @optional_attrs{'of', 'from'} = prompt_yes_or_no($question) ? ($of, $from) : ('', '');
        }

        my $section_name;
        if ($file->{timestamp}) {
            my ($year, $mm, $dd) = Scramble::Time::parse_date_and_time($file->{timestamp});
            $section_name = $sections->{"$year/$mm/$dd"};
        }

        push @file_xmls, $xg->file({ %optional_attrs,
                                         'description' => $file->{caption},
                                         'thumbnail-filename' => $file->{thumb_filename},
                                         'large-filename' => $file->{enl_filename},
                                         rating => $file->{rating},
                                         type => $file->{type},
                                         owner => $file->{owner},
                                         'capture-timestamp' => $file->{timestamp},
                                         'section-name' => $section_name,
                                   });
    }

    return $xg->files({ date => $date,
                        'in-chronological-order' => "true",
                        'trip-id' => 1,
                      },
                      @file_xmls);
}

sub make_locations_xml {
    my ($locations) = @_;

    my @location_attrs = map {
        {
            name => $_->get_name,
            quad => ($_->get_quad_objects)[0]->get_id,
        }
    } @$locations;

    return $xg->locations(map { $xg->location($_) } @location_attrs);
}


sub html {
    my %args = @_;

    $args{title} =~ s/&/&amp;/g; # It is still the dark ages here.

    my $files_xml = make_files_xml($args{image_data}{files}, $args{date}, $args{sections});
    my $locations_xml = make_locations_xml($args{locations});

    my $start = $args{gps_data}{start} || $args{image_data}{first_timestamp} || '';
    my $end = $args{gps_data}{end} || $args{image_data}{last_timestamp} || '';

    return <<EOT;
<trip filename="$args{image_subdir}"
      start-date="$args{date}"
      name="$args{title}"
      type="$args{trip_type}"
      trip-id="1"
>
    <description />
    <references />

    $locations_xml

    <party size="">
        <member name="Gabriel Deal" type="author"/>
        Lindsay Malone
    </party>

    <round-trip-distances>
        <distance type="foot" miles=""/>
        <distance type="bike" miles=""/>
    </round-trip-distances>

    <waypoints elevation-gain="">
        <waypoint type="ascending"
               location-description=""
               time="$start"
        />
        <waypoint type="break"
               location-description=""
               time="$end"
        />
    </waypoints>

    $files_xml
</trip>
EOT
}


1;
