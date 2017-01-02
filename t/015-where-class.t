#!/usr/bin/env perl6

use v6.c;

use Test;

use Squirrel;

my $where;

lives-ok {
    $where = Squirrel::Where.new( where => { a => 1, b => 2 }, logic => 'AND');
}

isa-ok $where, Squirrel::Where, "It's the right class";
is $where.sql, "WHERE a = ? AND b = ?", "got plausible SQL";
is-deeply $where.bind, [1,2], "and the bind is what we expected";

lives-ok {
    $where = Squirrel::Where.new(where => ('-or' => (a => 1, b => 2)));
}

isa-ok $where, Squirrel::Where, "It's the right class";
is $where.sql, "WHERE a = ? OR b = ?", "got plausible SQL";
is-deeply $where.bind, [1,2], "and the bind is what we expected";


done-testing;
# vim: expandtab shiftwidth=4 ft=perl6
