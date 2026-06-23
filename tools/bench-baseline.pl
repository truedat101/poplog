#!/usr/bin/env perl
# Perl baseline for tools/bench-poplog.p -- the workloads Perl maps cleanly
# (nfib + intloop), same rigorous protocol (CPU-time, calibration, warm-up,
# N runs).
#
# Timer: (times())[0,1] -- process CPU time (user+system), matching Poplog
# systime() and Python process_time().  Emits:
#     SAMPLE <workload> <batch-microseconds> <iterations-K>
# plus META/CALIB lines.  tools/bench-aggregate.py computes statistics.
# Tunables: BENCH_RUNS, BENCH_WARMUP, BENCH_MINTIME (seconds of CPU time).
use strict;
use warnings;

my $RUNS    = $ENV{BENCH_RUNS}    // 30;
my $WARMUP  = $ENV{BENCH_WARMUP}  // 3;
my $MINTIME = $ENV{BENCH_MINTIME} // 2.0;   # seconds of CPU time

sub now { my @t = times(); return $t[0] + $t[1]; }   # user + system CPU

sub runk { my ($f, $k) = @_; $f->() for (1 .. $k); }

sub calibrate {
    my ($f) = @_;
    my $k = 1;
    while (1) {
        my $t0 = now(); runk($f, $k); my $dt = now() - $t0;
        return $k if $dt >= $MINTIME or $k >= 100_000_000;
        my $grow = $dt > 0 ? int($k * ($MINTIME + 0.001) / $dt) : $k * 2;
        $k = $grow > $k * 2 ? $grow : $k * 2;
    }
}

sub measure {
    my ($name, $f) = @_;
    my $k = calibrate($f);
    for (1 .. $WARMUP) { my $t0 = now(); runk($f, $k); now(); }
    print "CALIB\t$name\t$k\n";
    for (1 .. $RUNS) {
        my $t0 = now(); runk($f, $k); my $dt = now() - $t0;
        printf "SAMPLE\t%s\t%d\t%d\n", $name, int($dt * 1_000_000 + 0.5), $k;
    }
}

# ---- workloads -------------------------------------------------------------

sub nfib { my $n = shift; $n < 2 ? 1 : nfib($n - 1) + nfib($n - 2) + 1 }
sub w_nfib { nfib(29) }

sub w_intloop { my $s = 0; $s += $_ for 1 .. 10_000_000; }

# ---- driver ----------------------------------------------------------------

$| = 1;
print "META\tengine=perl\tversion=$]\truns=$RUNS\twarmup=$WARMUP"
    . "\tmintime_s=$MINTIME\ttimer=times-cpu\n";

measure("nfib29",     \&w_nfib);
measure("intloop10M", \&w_intloop);

print "bench-done perl $]\n";
