use strict;
print "<locations>\n";
while (defined(my $line = <>)) {
    next if $line =~ /^\s*$/;
    next if $line =~ /^RANK/;
    $line =~ s/\([^\(\)]+\)//;
    my ($rank, $peak, $elev, $quad) = ($line =~ /^\s*(\d+)\s+([^\d]+)\s+(\d+\+?)\s+([^\d]+)\s+\w+\s*$/);
    $quad or (print("Die ($rank, $peak, $elev, $quad): '$line'"), die $line);
    my $unofficial = '0';
    if ($peak =~ s/ \*|\]|\[//g) {
	$unofficial = 'true';
    }
    $peak = transform($peak);
    $quad = transform($quad);
    print qq(<location order="$rank" name="$peak" unofficial-name="$unofficial" elevation="$elev" quad="$quad"/>\n);
}
print "</locations>\n";

sub transform {
    my $peak = shift;
    $peak =~ s/Lk\./Lake/;
    $peak =~ s/Pk\./Peak/;
    $peak =~ s/Mtns\./Mountains/;
    $peak =~ s/Mtn\./Mountain/;
    $peak =~ s/Mt\./Mount/;
    $peak = join(' ', map { ucfirst(lc $_) } split(/\s+/, $peak));
    $peak =~ s/St. /Saint /;
    return $peak;
}
