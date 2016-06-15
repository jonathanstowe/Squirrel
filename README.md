# Squirrel

Simplified abstraction for SQL generation

## Synopsis

```perl6

use Squirrel;

my $s = Squirrel.new;

my ($sql, @bind) = $s.select('foo', *, where => bar => 3); "select * from foo where bar = ?", [3];


```


## Description

This is totally experimental.

This started out as an attempt to make a rudimentary port of
[SQL::Abstract](https://metacpan.org/release/SQL-Abstract) to
Perl 6, however the more I thought about it I realised that
the resulting interface would be horrible in Perl 6, so whilst
it may have some superficial similarities, it will probably
diverge quite a lot in detail.

