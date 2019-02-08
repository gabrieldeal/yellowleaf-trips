package Scramble::Build::Writer;

use strict;

use Scramble::Logger ();

sub new {
    my ($arg0, $output_dir) = @_;

    my $self = {
        output_dir => $output_dir,
    };

    return bless($self, ref($arg0) || $arg0);
}

sub create {
    my $self = shift;
    my ($path, $contents) = @_;

    $path = "$self->{output_dir}/g/$path";
    Scramble::Logger::verbose "Creating $path\n";

    my $ofh = IO::File->new($path, "w")
	or die "Unable to open '$path': $!";
    $ofh->print($contents) or die "Failed to write to '$path': $!";
    $ofh->close() or die "Failed to flush to '$path': $!";
}

1;
