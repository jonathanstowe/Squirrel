#!/usr/bin/env perl6

use v6;

use Test;

use Squirrel;

my $order;

lives-ok { $order = Squirrel::OrderBy.new(order => <foo bar baz>) }, "order by object";

is $order.sql, "ORDER BY foo, bar, baz", "basic order correct";

lives-ok { $order = Squirrel::OrderBy.new(order => ( desc => 'foo', 'bar', asc => 'baz')) }, "order by with modifiers";

is $order.sql, "ORDER BY foo DESC, bar, baz ASC", "order has directions";


done-testing;
# vim: expandtab shiftwidth=4 ft=perl6
