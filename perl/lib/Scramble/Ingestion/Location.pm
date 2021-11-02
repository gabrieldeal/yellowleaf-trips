package Scramble::Ingestion::Location;

use strict;

use Getopt::Long ();
use IO::File;
use Scramble::Misc ();
use Scramble::Ingestion::PeakList::ListsOfJohn ();

sub new {
    my ($arg0, %args) = @_;

    my $self = { %args };
    bless($self, ref($arg0) || $arg0);

    return $self;
}

sub create {
    my $self = shift;

    my @peaks;
    foreach my $name (sort keys %Scramble::Ingestion::PeakList::ListsOfJohn::Peaks) {
        next unless $name =~ /$self->{name}/i;
        push @peaks, values %{ $Scramble::Ingestion::PeakList::ListsOfJohn::Peaks{$name} };
    }
    if (! @peaks) {
        printf("Lists of John has no such peak '%s'", $self->{name});
        return 1;
    }

    my @choices = map {
        {
            name => "$_->{name} ($_->{quad})",
            value => $_,
        }
    } @peaks;
    my $peak = Scramble::Misc::choose_interactive(@choices);

    my $filename = Scramble::Misc::sanitize_for_filename($peak->{name});
    $filename = $self->{output_dir} . "/$filename.xml";
    die "$filename already exists" if -e $filename;

    my $xml = make_location_xml($peak);

    my $fh = IO::File->new($filename, "w") or die "Can't open $filename: $!";
    $fh->print($xml);
    $fh->close;

    print "Created $filename\n";

    return 0;
}

# FIXME: Move into a Controller/LocationXml.pm
sub make_location_xml {
    my ($peak) = @_;

    my $unofficial_name = $peak->{'unofficial-name'} ? 1 : 0;

    return <<EOT;
<location
    type="peak"
    elevation="$peak->{elevation}"
    prominence="$peak->{prominence}"
>

    <name value="$peak->{name}"
          unofficial-name="$unofficial_name"
    />

    <coordinates datum="WGS84"
                 latitude="$peak->{coordinates}{latitude}"
    	     longitude="$peak->{coordinates}{longitude}"
    />

    <areas>
        <area id="WA"/>
        <area id="$peak->{quad}"/>
    </areas>

</location>
EOT
}

1;
