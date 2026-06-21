#!/usr/bin/perl
#
# strip-changelog-metadata.pl — the single source of truth for the deploy-time
# changelog cleaner's KTD2 grammar (DMNC-1147): strips the {tour:} marker and
# the trailing developer-metadata run from each line, iteratively so a chained
# "— A — B" run is fully removed. A trailing em-dash segment that does NOT start
# with a known issue token (a prose em-dash) is left intact.
#
# This is the perl twin of Swift ChangelogParser.stripTrailingMetadata. Both are
# pinned to the same expected outputs — perl by scripts/check-changelog-parity.sh,
# Swift by ChangelogParserTests — so a drift in either fails its own check.
#
# [ \t]* (not \s*) at the tail so the iterative strip never eats the line's own
# newline and collapses adjacent bullets together (see the dual-implementation
# parity solution doc).
#
# Reads lines on stdin; writes the stripped lines to stdout.
use strict;
use warnings;
binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");

my $token = qr/DMNC-\d+|PR\ \#\d+|R\d+|AE\d+|D\d+|[A-Z]{2,}-\d+/;

while (<STDIN>) {
    s/[ \t]*\{tour:[^}]*\}//g;
    1 while s/[ \t]+\x{2014}[ \t]+(?:$token)(?:,?[ \t]+(?:$token|[a-z][a-z-]+|\([^)]*\)))*\.?[ \t]*$//;
    print;
}
