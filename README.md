# Squirrel

Simplified abstraction for SQL generation

## Synopsis

```perl6

use Squirrel;

my $s = Squirrel.new;

my ($sql, @bind) = $s.select('foo', *, where => bar => 3); # "select * from foo where bar = ?", [3];


```


## Description

This is totally experimental, and you don't want to use it if you want
something stable.

This started out as an attempt to make a rudimentary port of
[SQL::Abstract](https://metacpan.org/release/SQL-Abstract) to Perl 6,
however the more I thought about it I realised that the resulting
interface would be horrible in Perl 6, so whilst it may have some
superficial similarities, it will probably diverge quite a lot in detail.


## Installation

Assuming you have a working Rakudo Perl 6 installation you should be able
to install this with ```panda``` :

	panda install Squirrel

or from this distribution directory:

	panda install .

I'm fairly certain it will work with ```zef``` too, I just haven't tested that.

## Support

This is experimental. It probably doesn't do what you want and I am open
to suggestion, though I'd be equally happy for you to make something better
or more consistent to your expectations.

Please send a PR or raise an issue at https://github.com/jonathanstowe/Squirrel/issues

## Copyright and Licence

This is free software, please see the [LICENCE](LICENCE) file in the
distribution for details.

© Jonathan Stowe 2016, 2017
