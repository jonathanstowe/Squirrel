#!/usr/bin/env perl6

use v6.c;

use Test;

use Squirrel;

my $where;

my $*SQUIRREL-DEBUG = True;

lives-ok {
    $where = Squirrel::Where.new(a => 1, b => 2);
}

isa-ok $where, Squirrel::Where, "It's the right class";
is $where.sql, "WHERE a = ? AND b = ?", "got plausible SQL";
is-deeply $where.bind, [1,2], "and the bind is what we expected";
diag $where.sql.perl;

lives-ok {
    $where = Squirrel::Where.new('-or' => (a => 1, b => 2));
}

isa-ok $where, Squirrel::Where, "It's the right class";
is $where.sql, "WHERE a = ? OR b = ?", "got plausible SQL";
is-deeply $where.bind, [1,2], "and the bind is what we expected";
diag $where.sql.perl;


done-testing;
# vim: expandtab shiftwidth=4 ft=perl6