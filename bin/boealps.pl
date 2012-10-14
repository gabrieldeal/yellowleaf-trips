use strict;

print "<locations>\n";
my $count = 0;
my @data;
while (defined(my $line = <>)) {
    $line =~ s/^\s*//;
    $line =~ s/\s*$//;
    next unless $line =~ /\S/;
    push @data, $line;
    if (++$count == 4) {
	$count = 0;
	transform(@data);
	@data = ();
    } 
}
transform(@data);
print "</locations>\n";
exit(0);

sub transform {
    my (@data) = @_;

    $data[3] =~ s/Lk\.?$/Lake/;
    $data[3] =~ s/Pk\.?$/Peak/;
    $data[3] =~ s/Mtns\.?$/Mountains/;
    $data[3] =~ s/Mtn\.?$/Mountain/;
    $data[3] =~ s/^Mt\.? /Mount /;

    printf(qq(<location county="%s" name="%s" elevation="%s" quad="%s"/>\n),
	   @data);
}
