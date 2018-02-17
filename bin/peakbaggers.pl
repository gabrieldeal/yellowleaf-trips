print "<locations>\n";
my $count = 0;
my $data;
while (defined(my $line = <>)) {
    $line =~ s/^\s*//;
    $line =~ s/\s*$//;
    if ($line =~ /^\d+$/ && $line == $count + 1 || $line == $count) {
	$count++;
	transform($data);
	$data = $line;
    } else {
	$data .= "| $line";
    }
}
transform($data);
print "</locations>\n";
exit(0);

sub transform {
    my $quad = shift;

    my $o = $quad;

    $quad =~ s/\| \| \| /\|/g;
    $quad =~ s/Lk\./Lake/;
    $quad =~ s/Pk\./Peak/;
    $quad =~ s/Mtns\./Mountains/;
    $quad =~ s/Mtn\./Mountain/;
    $quad =~ s/Mt\./Mount/;
    $quad =~ s/\|\s*$//;
    my $cag = ($quad =~ /\bCAG\b/ ? "becky1" : '');
    my @d = split /\|/, $quad;

    my $unofficial = ($d[1] =~ s/\s*\*// ? "true" : '0');

    print sprintf(qq(<location order="%s" name="%s" unofficial-name="%s" elevation="%s" prominence="%s" quad="%s" references="%s"/>\n), 
		  @d[0, 1], 
		  $unofficial, 
		  @d[2,4,5], 
		  $cag);
}
