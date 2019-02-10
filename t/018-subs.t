#!/usr/bin/env perl6

use v6;

use Test;

use Squirrel;

my $obj;

lives-ok { $obj = SQL('length(?)', 'foo') }, "SQL";

ok $obj ~~ Squirrel::SqlLiteral, "got an SqlLiteral";
is $obj.sql, 'length(?)', "got the expected SQL";
is $obj.bind.elems, 1, "got one elem in bind";
is $obj.bind[0], 'foo', "and it's the right thing";


done-testing;
# vim: expandtab shiftwidth=4 ft=perl6
