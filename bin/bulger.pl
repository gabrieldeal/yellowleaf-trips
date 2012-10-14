use strict;
print "<locations>\n";
while (defined(my $line = <>)) {
    next if $line =~ /^\s*$/;
    next if $line =~ /^RANK/;
    $line =~ s/\([^\(\)]+\)//;
    my ($rank, $peak, $elev, $m, $quad) = ($line =~ /^(\d+) ([^\d]+) (\d+\+?) (\d+\+?) ([^\d]+) \d/);
    $quad or (print("$line"), die $line);
    my $unofficial = '0';
    if ($peak =~ s/^'(.+)'$/$1/) {
	$unofficial = 'true';
    }
    $peak = transform($peak);
    $quad = transform($quad);
    print qq(<location order="$rank" name="$peak" unofficial-name="$unofficial" elevation="$elev" quad="$quad"/>\n);
}
print "</locations>\n";

sub transform {
    my $peak = shift;
    $peak =~ s/ MTN/ Mountain/;
    $peak =~ s/MTS$/Mountains/;
    $peak =~ s/MT /Mount /;
    $peak = join(' ', map { ucfirst(lc $_) } split(/\s+/, $peak));
    $peak =~ s/St. /Saint /;
    return $peak;
}
