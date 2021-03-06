#!/usr/bin/env perl6

use v6;

use Test;

use Squirrel;


# This is only testing the non-transitional syntax
my @tests = (
    {
        where => {
            requestor => 'inna',
            worker => ['nwiger', 'rcwe', 'sfz'],
            status => { '!=' => 'completed' }
        },
        stmt => "WHERE requestor = ? AND status != ? AND ( worker = ? OR worker = ? OR worker = ? )",
        bind => [qw/inna completed nwiger rcwe sfz/],
    },
    {
        where  => [
            status => 'completed',
            user   => 'nwiger',
        ],
        stmt => "WHERE status = ? OR user = ?",
        bind => [qw/completed nwiger/],
    },


    {
        where  => {
            user   => 'nwiger',
            status => { '!=' => 'completed' }
        },
        stmt => "WHERE status != ? AND user = ?",
        bind => [qw/completed nwiger/],
    },

    {
        where  => {
            status   => 'completed',
            reportid => { 'in' =>  [567, 2335, 2] }
        },
        stmt => "WHERE reportid IN ( ?, ?, ? ) AND status = ?",
        bind => [567,2335,2, 'completed'],
    },

    {
        where  => {
            status   => 'completed',
            reportid => { 'not in' => [567, 2335, 2] }
        },
        stmt => "WHERE reportid NOT IN ( ?, ?, ? ) AND status = ?",
        bind => [567, 2335,2,  'completed'],
    },

    {
        where  => {
            status   => 'completed',
            completion_date => { 'between' => ['2002-10-01', '2003-02-06'] },
        },
        stmt => "WHERE ( completion_date BETWEEN ? AND ? ) AND status = ?",
        bind => [qw/2002-10-01 2003-02-06 completed/],
    },

    {
        where => [
            {
                user   => 'nwiger',
                status => { 'in' => ['pending', 'dispatched'] },
            },
            {
                user   => 'robot',
                status => 'unassigned',
            },
        ],
        stmt => "WHERE ( status IN ( ?, ? ) AND user = ? ) OR ( status = ? AND user = ? )",
        bind => [qw/pending dispatched nwiger unassigned robot/],
    },

    {
        where => {
            priority  => [ {'>' => 3}, {'<' => 1} ],
            requestor => SQL('is not null'),
        },
        stmt => "WHERE ( priority > ? OR priority < ? ) AND requestor is not null",
        bind => [3, 1],
    },

    {
        where => {
            requestor => { '!=' => ['-and', Any, ''] },
        },
        stmt => "WHERE requestor IS NOT NULL AND requestor != ?",
        bind => [''],
    },

    {
        where => {
            priority  => [ {'>' => 3}, {'<' => 1} ],
            requestor => { '!=' => Any },
        },
        stmt => 'WHERE ( priority > ? OR priority < ? ) AND requestor IS NOT NULL',
        bind => [3,1],
    },

    {
        where => {
            priority  => { 'between' => [1, 3] },
            requestor => { 'like' => Any },
        },
        stmt => 'WHERE ( priority BETWEEN ? AND ? ) AND requestor IS NULL',
        bind => [1,3],
    },


    {
        where => {
          id  => 1,
          num => {
           '<=' => 20,
           '>'  => 10,
          },
        },
        stmt => 'WHERE id = ? AND ( num <= ? AND num > ? )',
        bind => [1,20,10],
    },

    {
        where => { foo => {'-not_like' => [7,8,9]},
                   fum => {'like' => [qw/a b/]},
                   nix => {'between' => [100,200] },
                   nox => {'not between' => [150,160] },
                   wix => {'in' => [qw/zz yy/]},
                   wux => {'not_in'  => [qw/30 40/]}
                 },
        stmt => 'WHERE ( foo NOT LIKE ? OR foo NOT LIKE ? OR foo NOT LIKE ? ) AND ( fum LIKE ? OR fum LIKE ? ) AND ( nix BETWEEN ? AND ? ) AND ( nox NOT BETWEEN ? AND ? ) AND wix IN ( ?, ? ) AND wux NOT IN ( ?, ? )',
        bind => [7,8,9,'a','b',100,200,150,160,'zz','yy','30','40'],
    },

    {
        where => {
            bar => {'!=' => []},
        },
        stmt => "WHERE 1=1",
        bind => [],
    },

    {
        where => {
            id  => [],
        },
        stmt => "WHERE 0=1",
        bind => [],
    },


    {
        where => {
            foo => SQL("IN (?, ?)", 22, 33),
            bar => {"-and" =>  (SQL("> ?", 44), SQL("< ?", 55)) },
        },
        stmt => 'WHERE ( bar > ? AND bar < ? ) AND foo IN (?, ?)',
        bind => [44, 55, 22, 33],
    },

    {
        where => {
          "-and" => [
            user => 'nwiger',
            [
              "-and" => [ workhrs => {'>' => 20}, geo => 'ASIA' ],
              "-or" => { workhrs => {'<' => 50}, geo => 'EURO' },
            ],
          ],
        },
        stmt => 'WHERE ( user = ? AND ( ( workhrs > ? AND geo = ? ) AND ( geo = ? OR workhrs < ? ) ) )',
        bind => ["nwiger", 20,  "ASIA",  "EURO", 50],
    },

   {
       where => { "-and" => [{}, { 'me.id' => 1}] },
       stmt => "WHERE ( ( me.id = ? ) )",
       bind => [ 1 ],
   },

   {
       where => SQL('foo = ?','bar' ),
       stmt => "WHERE foo = ?",
       bind => [ "bar" ],
   },

   {
       where => { "-bool" => SQL('function(x)') },
       stmt => 'WHERE function(x)',
       bind => [],
   },

   {
       where => { "-bool" => 'foo' },
       stmt => "WHERE foo",
       bind => [],
   },

   {
       where => { "-and" => ["-bool" => 'foo', "-bool" => 'bar'] },
       stmt => 'WHERE ( foo AND bar )',
       bind => [],
   },

   {
       where => { "-or" => ["-bool" => 'foo', "-bool" => 'bar'] },
       stmt => 'WHERE ( foo OR bar )',
       bind => [],
   },

   {
       where => { "-not_bool" => SQL('function(x)') },
       stmt => 'WHERE NOT function(x)',
       bind => [],
   },

   {
       where => { "-not_bool" => 'foo' },
       stmt => 'WHERE NOT foo',
       bind => [],
   },

   {
       where => { "-and" => ["-not_bool" => 'foo', "-not_bool" => 'bar'] },
       stmt => 'WHERE ( NOT foo AND NOT bar )',
       bind => [],
   },

   {
       where => { "-or" => ["-not_bool" => 'foo', "-not_bool" => 'bar'] },
       stmt => 'WHERE ( NOT foo OR NOT bar )',
       bind => [],
   },

   {
       where => { "-bool" => SQL('function(?)', 20)  },
       stmt => "WHERE function(?)",
       bind => [20],
   },

   {
       where => { "-not_bool" => SQL('function(?)', 20)  },
       stmt => 'WHERE NOT function(?)',
       bind => [20],
   },

   {
       where => { "-bool" => { a => 1, b => 2}  },
       stmt => "WHERE a = ? AND b = ?",
       bind => [1, 2],
   },

   {
       where => { "-bool" => [ a => 1, b => 2] },
       stmt => 'WHERE a = ? OR b = ?',
       bind => [1, 2],
   },

   {
       where => { "-not_bool" => { a => 1, b => 2}  },
       stmt => 'WHERE NOT ( a = ? AND b = ? )',
       bind => [1, 2],
   },

   {
       where => { "-not_bool" => [ a => 1, b => 2] },
       stmt => 'WHERE NOT ( a = ? OR b = ? )',
       bind => [1, 2],
   },

   {
       where => { bool1 => { '=' => { "-not_bool" => 'bool2' } } },
       stmt => "WHERE bool1 = ( NOT bool2 )",
       bind => [],
   },
   {
       where => { "-not_bool" => { "-not_bool" => { "-not_bool" => 'bool2' } } },
       stmt => 'WHERE NOT ( NOT ( NOT bool2 ) )',
       bind => [],
   },

   {
       where => { timestamp => { '!=' => { "-trunc" => { "-year" => SQL('sysdate') } } } },
       stmt => 'WHERE timestamp != ( TRUNC ( YEAR sysdate ) )',
       bind => [],
   },
   {
       where => { timestamp => { '>=' => { "-to_date" => '2009-12-21 00:00:00' } } },
       stmt => 'WHERE timestamp >= ( TO_DATE ? )',
       bind => ['2009-12-21 00:00:00'],
   },
   {
       where => { ip => {'<<=' => '127.0.0.1/32' } },
       stmt => "WHERE ip <<= ?",
       bind => ['127.0.0.1/32'],
   },
   {
       where => { foo => { 'GLOB' => '*str*' } },
       stmt => "WHERE foo GLOB ?",
       bind => [ '*str*' ],
   },
   {
       where => { foo => { 'REGEXP' => 'bar|baz' } },
       stmt => "WHERE foo REGEXP ?",
       bind => [ 'bar|baz' ],
   },
    {
        where => { "-not" => { a => 1 } },
        stmt  => "WHERE NOT ( a = ? )",
        bind => [ 1 ],
    },
    {
        where => { a => 1, "-not" => { b => 2 } },
        stmt  => 'WHERE NOT ( b = ? ) AND a = ?',
        bind => [ 2, 1 ],
    },
    {
        where => { "-not" => { a => 1, b => 2, c => 3 } },
        stmt  => "WHERE NOT ( a = ? AND b = ? AND c = ? )",
        bind => [ 1, 2, 3 ],
    },
    {
        where => { "-not" => [ a => 1, b => 2, c => 3 ] },
        stmt  => 'WHERE NOT ( a = ? OR b = ? OR c = ? )',
        bind => [ 1, 2, 3 ],
    },
    {
        where => { "-not" => { c => 3, "-not" => { b => 2, "-not" => { a => 1 } } } },
        stmt  => 'WHERE NOT ( NOT ( NOT ( a = ? ) AND b = ? ) AND c = ? )',
        bind => [ 1, 2, 3 ],
    },
    {
        where => { "-not" => { "-bool" => 'c', "-not" => { "-not_bool" => 'b', "-not" => { a => 1 } } } },
        stmt  => "WHERE NOT ( c AND NOT ( NOT ( a = ? ) AND NOT b ) )",
        bind => [ 1 ],
    },
    {
        where   => { a => {'>' =>  SQL('1 + 1')}, b => 8 },
        stmt    => 'WHERE a > 1 + 1 AND b = ?',
        bind    =>  [ 8 ],
    },
    {
        where   => { a =>  '!=' => 'boom' },
        stmt    => 'WHERE a != ?',
        bind    =>  ['boom' ],
    }

);

multi sub MAIN(Bool :$debug, Int :$from, Int :$to, Int :$only) {

    my $range;
    if $from.defined && $to.defined {
        $range = $from .. $to;
    }
    else {
        $range = $only // $from // $to // ^(@tests.elems);
    }


    my $*SQUIRREL-DEBUG = $debug;
    my $s = Squirrel.new(:$debug);
    for @tests[$range.list] -> $test  {
        subtest {
    	    my @res;
            #lives-ok {
    	        @res = $s.where(where => $test<where>) ;
            #}, "do where";
            is @res[0], $test<stmt>, "got the SQL expected";
            is-deeply @res[1].Array, $test<bind>.Array, "got the expected bind";
        }, "where test " ~ $++;
    }

    done-testing;
}



# vim: expandtab shiftwidth=4 ft=perl6
