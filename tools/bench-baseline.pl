#!/usr/bin/env perl
# Perl baseline: the two headline workloads (calls + loop), centiseconds.
use strict; use warnings; use Time::HiRes qw(time);
sub nfib { my $n = shift; $n < 2 ? 1 : nfib($n-1) + nfib($n-2) + 1 }
my $t0 = time; nfib(29);
printf "nfib29-calls: %d\n", (time - $t0) * 100;
$t0 = time; my $s = 0; $s += $_ for 1..10000000;
printf "intloop10M: %d\n", (time - $t0) * 100;
print "bench-done perl $]\n";
