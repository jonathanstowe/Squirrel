#!/usr/bin/env perl6

use v6.c;

use Test;

use Squirrel;

sub prefix:<-> (Pair $p) { "-{$p.key}" => $p.value }

my @tests = 
      {
              func   => 'select',
              args   => ['test', '*'],
              stmt   => 'SELECT * FROM test',
              stmt_q => 'SELECT * FROM `test`',
              bind   => ()
      },
      {
              func   => 'select',
              args   => ['test', [<one two three>]],
              stmt   => 'SELECT one, two, three FROM test',
              stmt_q => 'SELECT `one`, `two`, `three` FROM `test`',
              bind   => ()
      },
      {
              func   => 'select',
              args   => \('test', '*', where => {a => 0} , order => <boom bada bing>),
              stmt   => 'SELECT * FROM test WHERE ( a = ? ) ORDER BY boom, bada, bing',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` = ? ) ORDER BY `boom`, `bada`, `bing`',
              bind   => (0)
      },
      {
              func   => 'select',
              args   => \('test', '*', where => ( { a => 5 }, { b => 6 } )),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a = ? ) OR ( b = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( ( `a` = ? ) OR ( `b` = ? ) )',
              bind   => (5,6)
      },
      {
              func   => 'select',
              args   => \('test', '*', order => ('id')),
              stmt   => 'SELECT * FROM test ORDER BY id',
              stmt_q => 'SELECT * FROM `test` ORDER BY `id`',
              bind   => ()
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => 'boom' } , order => ('id')),
              stmt   => 'SELECT * FROM test WHERE ( a = ? ) ORDER BY id',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` = ? ) ORDER BY `id`',
              bind   => ('boom')
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => ('boom', 'bang') }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a = ? ) OR ( a = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( ( ( `a` = ? ) OR ( `a` = ? ) ) )',
              bind   => ('boom', 'bang')
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a =>  '!=' => 'boom' }),
              stmt   => 'SELECT * FROM test WHERE ( a != ? )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` != ? )',
              bind   => ('boom')
      },
      {
              func   => 'update',
              args   => \('test', {a => 'boom'}, where => {a => Any}),
              stmt   => 'UPDATE test SET a = ? WHERE ( a IS NULL )',
              stmt_q => 'UPDATE `test` SET `a` = ? WHERE ( `a` IS NULL )',
              bind   => ('boom')
      },
      {
              func   => 'update',
              args   => \('test', {a => 'boom'}, where => { a => {'!=' => "bang" }} ),
              stmt   => 'UPDATE test SET a = ? WHERE ( a != ? )',
              stmt_q => 'UPDATE `test` SET `a` = ? WHERE ( `a` != ? )',
              bind   => ('boom', 'bang')
      },
      {
              func   => 'update',
              args   => \('test', {'a-funny-flavored-candy' => 'yummy', b => 'oops'}, where => { a42 => "bang" }),
              stmt   => 'UPDATE test SET a-funny-flavored-candy = ?, b = ? WHERE ( a42 = ? )',
              stmt_q => 'UPDATE `test` SET `a-funny-flavored-candy` = ?, `b` = ? WHERE ( `a42` = ? )',
              bind   => ('yummy', 'oops', 'bang')
      },
      {
              func   => 'delete',
              args   => \('test', where => {requestor => Any}),
              stmt   => 'DELETE FROM test WHERE ( requestor IS NULL )',
              stmt_q => 'DELETE FROM `test` WHERE ( `requestor` IS NULL )',
              bind   => ()
      },
      {
              func   => 'delete',
              args   => \((<test1 test2 test3>),
                         where => { 'test1.field' => \'!= test2.field',
                            user => {'!=','nwiger'} },
                        ),
              stmt   => 'DELETE FROM test1, test2, test3 WHERE ( ( ( test1.field != test2.field ) AND ( user != ? ) ) )',
              stmt_q => 'DELETE FROM `test1`, `test2`, `test3` WHERE ( `test1`.`field` != test2.field AND `user` != ? )', 
              bind   => ('nwiger')
      },
      {
              func   => 'select',
              args   => \(('test1', 'test2'), '*', where => { 'test1.a' => 'boom' } ),
              stmt   => 'SELECT * FROM test1, test2 WHERE ( test1.a = ? )',
              stmt_q => 'SELECT * FROM test1, `test2` WHERE ( `test1`.`a` = ? )',
              bind   => ('boom')
      },
# Ok
      {
              func   => 'insert',
              args   => \('test', {a => 1, b => 2, c => 3, d => 4, e => 5}),
              stmt   => 'INSERT INTO test (a, b, c, d, e) VALUES (?, ?, ?, ?, ?)',
              stmt_q => 'INSERT INTO `test` (`a`, `b`, `c`, `d`, `e`) VALUES (?, ?, ?, ?, ?)',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'insert',
              args   => \('test', (1..30)),
              stmt   => 'INSERT INTO test VALUES (' ~ join(', ', ('?') xx 30) ~ ')',
              stmt_q => 'INSERT INTO `test` VALUES (' ~ join(', ', ('?') xx 30) ~ ')',
              bind   => (1..30),
      },
      {
              func   => 'insert',
              args   => \('test', (1, 2, 3, 4, 5, Any)),
              stmt   => 'INSERT INTO test VALUES (?, ?, ?, ?, ?, ?)',
              stmt_q => 'INSERT INTO `test` VALUES (?, ?, ?, ?, ?, ?)',
              bind   => (1, 2,3,4,5, Any),
      },
      {
              func   => 'update',
              args   => ('test', {a => 1, b => 2, c => 3, d => 4, e => 5}),
              stmt   => 'UPDATE test SET a = ?, b = ?, c = ?, d = ?, e = ?',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = ?, `c` = ?, `d` = ?, `e` = ?',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'update',
              args   => \('test', {a => 1, b => 2, c => 3, d => 4, e => 5}, where => {a => {'in', (1..5)}}),
              stmt   => 'UPDATE test SET a = ?, b = ?, c = ?, d = ?, e = ? WHERE ( a IN ( ?, ?, ?, ?, ? ) )',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = ?, `c` = ?, `d` = ?, `e` = ? WHERE ( `a` IN ( ?, ?, ?, ?, ? ) )',
              bind   => (qw/1 2 3 4 5 1 2 3 4 5/),
      },
      {
              func   => 'update',
              args   => \('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", '02/02/02')}, where => {a => {'between' => (1,2)}}),
              stmt   => 'UPDATE test SET a = ?, b = to_date(?, \'MM/DD/YY\') WHERE ( ( a BETWEEN ? AND ? ) )',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = to_date(?, \'MM/DD/YY\') WHERE ( `a` BETWEEN ? AND ? )',
              bind   => (<1 02/02/02 1 2>),
      },
      {
              func   => 'insert',
              args   => ('test.table', {high_limit => \'max(all_limits)', low_limit => 4} ),
              stmt   => 'INSERT INTO test.table (high_limit, low_limit) VALUES (max(all_limits), ?)',
              stmt_q => 'INSERT INTO `test`.`table` (`high_limit`, `low_limit`) VALUES (max(all_limits), ?)',
              bind   => ('4'),
      },
      {
              func   => 'insert',
              args   => ('test.table', ( \'max(all_limits)', 4 ) ),
              stmt   => 'INSERT INTO test.table VALUES (max(all_limits), ?)',
              stmt_q => 'INSERT INTO `test`.`table` VALUES (max(all_limits), ?)',
              bind   => ('4'),
      },
      {
              func   => 'insert',
              new    => {bindtype => 'columns'},
              args   => ('test.table', {one => 2, three => 4, five => 6} ),
              stmt   => 'INSERT INTO test.table (five, one, three) VALUES (?, ?, ?)',
              stmt_q => 'INSERT INTO `test`.`table` (`five`, `one`, `three`) VALUES (?, ?, ?)',
              bind   => (('five' => 6), ('one' => 2), ('three' => 4)),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns', case => 'lower'},
              args   => \('test.table', (qw/one two three/), where => {one => 2, three => 4, five => 6} ),
              stmt   => 'select one, two, three from test.table where ( ( ( five = ? ) and ( one = ? ) and ( three = ? ) ) )',
              stmt_q => 'select `one`, `two`, `three` from `test`.`table` where ( ( `five` = ? and `one` = ? and `three` = ? ) ) )',
              bind   => (('five' => 6), ('one' => 2), ('three' => 4)), 
      },
      {
              func   => 'update',
              new    => {bindtype => 'columns', cmp => 'like'},
              args   => \('testin.table2', {One => 22, Three => 44, FIVE => 66},
                                          where => {Beer => 'is', Yummy => '%YES%', IT => ('IS','REALLY','GOOD')}),
              stmt   => 'UPDATE testin.table2 SET FIVE = ?, One = ?, Three = ? WHERE ( ( ( Beer LIKE ? ) AND ( ( ( IT LIKE ? ) OR ( IT LIKE ? ) OR ( IT LIKE ? ) ) ) AND ( Yummy LIKE ? ) ) )',
              stmt_q => 'UPDATE `testin`.`table2` SET `FIVE` = ?, `One` = ?, `Three` = ? WHERE '
                       ~ '( `Beer` LIKE ? AND ( ( `IT` LIKE ? ) OR ( `IT` LIKE ? ) OR ( `IT` LIKE ? ) ) AND `Yummy` LIKE ? )',
              bind   => (('FIVE' => 66), ('One' => 22), ('Three' => 44), ('Beer' => 'is'),
                         ('IT' => 'IS'), ('IT' => 'REALLY'), ('IT' => 'GOOD'), ('Yummy' => '%YES%')),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => {priority => ( -and => ({'!=', 2}, { -not_like => '3%'}) )}),
              stmt   => 'SELECT * FROM test WHERE ( ( ( priority != ? ) AND ( priority NOT LIKE ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( ( ( `priority` != ? ) AND ( `priority` NOT LIKE ? ) ) )',
              bind   => (2, '3%'),
      },
      {
              func   => 'select',
              args   => \('Yo Momma', '*', where => { user => 'nwiger',
                                       -nest => ( workhrs => {'>', 20}, geo => 'ASIA' ) }),
              stmt   => 'SELECT * FROM Yo Momma WHERE ( ( ( ( ( workhrs > ? ) OR ( geo = ? ) ) ) AND ( user = ? ) ) )',
              stmt_q => 'SELECT * FROM `Yo Momma` WHERE ( ( ( `workhrs` > ? ) OR ( `geo` = ? ) ) AND `user` = ? )',
              bind   => (<20 ASIA nwiger>),
      },
      {
              func   => 'update',
              args   => \('taco_punches', { one => 2, three => 4 },
                                         where => { bland => ( -and => {'!=', 'yes'}, {'!=', 'YES'} ),
                                           tasty => { '!=', (<yes YES>) },
                                           -nest => ( face => ( -or => {'=', 'mr.happy'}, {'=', Any} ) ) },
                        ),

              stmt   => 'UPDATE taco_punches SET one = ?, three = ? WHERE ( ( ( ( ( face = ? ) OR ( face IS NULL ) ) ) AND ( ( ( bland != ? ) OR ( bland != ? ) ) ) AND ( ( ( tasty != ? ) OR ( tasty != ? ) ) ) ) )',
              bind   => (<2 4 mr.happy yes YES yes YES>),
      },
      {
              func   => 'select',
              args   => \('jeff', '*', where => { name => {'ilike' => '%smith%', -not_in => ('Nate','Jim','Bob','Sally')},
                                       -nest => ( -or => ( -and => (age => { '-between' => (20,30), }, age => {'!=' => 25,} ),
                                                                   yob => {'<' => 1976,} ), ), } ),
              stmt   => 'SELECT * FROM jeff WHERE ( ( ( ( ( ( ( ( age BETWEEN ? AND ? ) ) AND ( age != ? ) ) ) OR ( yob < ? ) ) ) AND ( ( ( name NOT IN ( ?, ?, ?, ? ) ) AND ( name ILIKE ? ) )  ) ) )',
              bind   => (<20 30 25 1976 Nate Jim Bob Sally %smith%>)
      },
# bad
      {
              func   => 'update',
              args   => \('fhole', {fpoles => 4}, where => (
                          { race => (<-or black white asian>) },
                          { -nest => { firsttime => (-or => {'=','yes'}, Any) } },
                          { -and => ( { firstname => {-not_like => 'candace'} }, { lastname => {-in => (<jugs canyon towers>) } } ) },
                        ) ),
              stmt   => 'UPDATE fhole SET fpoles = ? WHERE ( ( ( ( ( race = ? ) OR ( race = ? ) OR ( race = ? ) ) ) OR ( ( ( firsttime = ? ) OR ( firsttime IS NULL ) ) ) OR ( ( ( firstname NOT LIKE ? ) AND ( lastname IN ( ?, ?, ? ) ) ) ) ) )',
              bind   => (<4 black white asian yes candace jugs canyon towers>)
      },
      {
              func   => 'insert',
              args   => ('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", '02/02/02')}),
              stmt   => 'INSERT INTO test (a, b) VALUES (?, to_date(?, \'MM/DD/YY\'))',
              stmt_q => 'INSERT INTO `test` (`a`, `b`) VALUES (?, to_date(?, \'MM/DD/YY\'))',
              bind   => (<1 02/02/02>),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => \("= to_date(?, 'MM/DD/YY')", '02/02/02')}),
              stmt   => q{SELECT * FROM test WHERE ( a = to_date(?, 'MM/DD/YY') )},
              stmt_q => q{SELECT * FROM `test` WHERE ( `a` = to_date(?, 'MM/DD/YY') )},
              bind   => ('02/02/02'),
      },
      {
              func   => 'insert',
              new    => {array-datatypes => 1},
              args   => ('test', {a => 1, b => (1, 1, 2, 3, 5, 8)}),
              stmt   => 'INSERT INTO test (a, b) VALUES (?, ?)',
              stmt_q => 'INSERT INTO `test` (`a`, `b`) VALUES (?, ?)',
              bind   => (1, (1, 1, 2, 3, 5, 8)),
      },
      {
              func   => 'insert',
              new    => {bindtype => 'columns', array-datatypes => 1},
              args   => ('test', {a => 1, b => (1, 1, 2, 3, 5, 8)}),
              stmt   => 'INSERT INTO test (a, b) VALUES (?, ?)',
              stmt_q => 'INSERT INTO `test` (`a`, `b`) VALUES (?, ?)',
              bind   => ((a => 1), (b => (1, 1, 2, 3, 5, 8))),
      },
      {
              func   => 'update',
              new    => {array-datatypes => 1},
              args   => ('test', {a => 1, b => (1, 1, 2, 3, 5, 8)}),
              stmt   => 'UPDATE test SET a = ?, b = ?',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = ?',
              bind   => (1, (1, 1, 2, 3, 5, 8)),
      },
      {
              func   => 'update',
              new    => {bindtype => 'columns', array-datatypes => 1},
              args   => ('test', {a => 1, b => (1, 1, 2, 3, 5, 8)}),
              stmt   => 'UPDATE test SET a = ?, b = ?',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = ?',
              bind   => ((a => 1), (b => (1, 1, 2, 3, 5, 8))),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => {'>' =>  \'1 + 1'}, b => 8 }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a > 1 + 1 ) AND ( b = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` > 1 + 1 AND `b` = ? )',
              bind   => (8),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => {'<' => \("to_date(?, 'MM/DD/YY')", '02/02/02')}, b => 8 }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a < to_date(?, \'MM/DD/YY\') ) AND ( b = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` < to_date(?, \'MM/DD/YY\') AND `b` = ? )',
              bind   => ('02/02/02', 8),
      },
      { 
              func   => 'insert',
              args   => ('test', {a => 1, b => 2, c => 3, d => 4, e => { answer => 42 }}),
              stmt   => 'INSERT INTO test (a, b, c, d, e) VALUES (?, ?, ?, ?, ?)',
              stmt_q => 'INSERT INTO `test` (`a`, `b`, `c`, `d`, `e`) VALUES (?, ?, ?, ?, ?)',
              bind   => (1, 2, 3, 4,  answer => 42),
      },
      {
              func   => 'update',
              args   => \('test', {a => 1, b => \("42") }, where => {a => {'between', (1,2)}}),
              stmt   => 'UPDATE test SET a = ?, b = 42 WHERE ( ( a BETWEEN ? AND ? ) )',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = 42 WHERE ( `a` BETWEEN ? AND ? )',
              bind   => (<1 1 2>),
      },
      {
              func   => 'insert',
              args   => ('test', {a => 1, b => \("42")}),
              stmt   => 'INSERT INTO test (a, b) VALUES (?, 42)',
              stmt_q => 'INSERT INTO `test` (`a`, `b`) VALUES (?, 42)',
              bind   => (<1>),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => \("= 42"), b => 1}),
              stmt   => q{SELECT * FROM test WHERE ( ( ( a = 42 ) AND ( b = ? ) ) )},
              stmt_q => q{SELECT * FROM `test` WHERE ( `a` = 42 ) AND ( `b` = ? )},
              bind   => (1,),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { a => {'<' => \("42")}, b => 8 }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a < 42 ) AND ( b = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` < 42 AND `b` = ? )',
              bind   => (8,),
      },
      {
              func   => 'insert',
              new    => {bindtype => 'columns'},
              args   => ('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", (dummy => '02/02/02'))}),
              stmt   => 'INSERT INTO test (a, b) VALUES (?, to_date(?, \'MM/DD/YY\'))',
              stmt_q => 'INSERT INTO `test` (`a`, `b`) VALUES (?, to_date(?, \'MM/DD/YY\'))',
              bind   => ((a => 1), (dummy => '02/02/02')),
      },
      {
              func   => 'update',
              new    => {bindtype => 'columns'},
              args   => \('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", (dummy => '02/02/02'))}, where => {a => {'between' => (1,2)}}),
              stmt   => 'UPDATE test SET a = ?, b = to_date(?, \'MM/DD/YY\') WHERE ( ( a BETWEEN ? AND ? ) )',
              stmt_q => 'UPDATE `test` SET `a` = ?, `b` = to_date(?, \'MM/DD/YY\') WHERE ( `a` BETWEEN ? AND ? )',
              bind   => ((a => 1), (dummy => '02/02/02'), (a => 1), (a => 2)),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => \("= to_date(?, 'MM/DD/YY')", (dummy => '02/02/02'))}),
              stmt   => q{SELECT * FROM test WHERE ( a = to_date(?, 'MM/DD/YY') )},
              stmt_q => q{SELECT * FROM `test` WHERE ( `a` = to_date(?, 'MM/DD/YY') )},
              bind   => ((dummy => '02/02/02')),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => {'<' => \("to_date(?, 'MM/DD/YY')", (dummy => '02/02/02'))}, b => 8 }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a < to_date(?, \'MM/DD/YY\') ) AND ( b = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` < to_date(?, \'MM/DD/YY\') AND `b` = ? )',
              bind   => ((dummy => '02/02/02'), (b => 8)),
      },
      {
              func   => 'insert',
              new    => {bindtype => 'columns'},
              args   => ('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", '02/02/02')}),
      },
      {
              func   => 'update',
              new    => {bindtype => 'columns'},
              args   => \('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", '02/02/02')}, where => {a => {'between', (1,2)}}),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => \("= to_date(?, 'MM/DD/YY')", '02/02/02')}),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => {'<' => \("to_date(?, 'MM/DD/YY')", '02/02/02')}, b => 8 }),
      },
      {
              func   => 'select',
              args   => \('test', '*', where => { foo => { '>=' => () }} ),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => {-in => \("(SELECT d FROM to_date(?, 'MM/DD/YY') AS d)", (dummy => '02/02/02')), }, b => 8 }),
              stmt   => "SELECT * FROM test WHERE ( ( ( a IN ( SELECT d FROM to_date(?, 'MM/DD/YY') AS d ) ) AND ( b = ? ) ) )",
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` IN (SELECT d FROM to_date(?, \'MM/DD/YY\') AS d) AND `b` = ? )',
              bind   => ((dummy => '02/02/02'), (b => 8)),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => {-in => \("(SELECT d FROM to_date(?, 'MM/DD/YY') AS d)", '02/02/02')}, b => 8 }),
      },
      {
              func   => 'insert',
              new    => {bindtype => 'columns'},
              args   => ('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", ({dummy => 1} => '02/02/02'))}),
              stmt   => 'INSERT INTO test (a, b) VALUES (?, to_date(?, \'MM/DD/YY\'))',
              stmt_q => 'INSERT INTO `test` (`a`, `b`) VALUES (?, to_date(?, \'MM/DD/YY\'))',
              bind   => ((a => 1), ({dummy => 1} => '02/02/02')),
      },
      {
              func   => 'update',
              new    => {bindtype => 'columns'},
              args   => \('test', {a => 1, b => \("to_date(?, 'MM/DD/YY')", ({dummy => 1} => '02/02/02')), c => { '-lower' => 'foo' }}, where => {a => {'between', (1,2)}}),
              stmt   => "UPDATE test SET a = ?, b = to_date(?, 'MM/DD/YY'), c = LOWER ? WHERE ( ( a BETWEEN ? AND ? ) )",
              stmt_q => "UPDATE `test` SET `a` = ?, `b` = to_date(?, 'MM/DD/YY'), `c` = LOWER ? WHERE ( `a` BETWEEN ? AND ? )",
              bind   => ((a => 1), ({dummy => 1} => '02/02/02'), (c => 'foo'), (a => 1), (a => 2)),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => \("= to_date(?, 'MM/DD/YY')", ({dummy => 1} => '02/02/02'))}),
              stmt   => q{SELECT * FROM test WHERE ( a = to_date(?, 'MM/DD/YY') )},
              stmt_q => q{SELECT * FROM `test` WHERE ( `a` = to_date(?, 'MM/DD/YY') )},
              bind   => (({dummy => 1} => '02/02/02')),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { a => {'<' => \("to_date(?, 'MM/DD/YY')", ({dummy => 1} => '02/02/02'))}, b => 8 }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( a < to_date(?, \'MM/DD/YY\') ) AND ( b = ? ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( ( ( `a` < to_date(?, \'MM/DD/YY\') AND `b` = ? )',
              bind   => (({dummy => 1} => '02/02/02'), (b => 8)),
      },
# these
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => { '-or' => ( '-and' => ( a => 'a', b => 'b', ), '-and' => ( c => 'c', d => 'd', ),  ), }),
              stmt   => 'SELECT * FROM test WHERE ( ( ( ( ( a = ? ) AND ( b = ? ) ) ) OR ( ( ( c = ? ) AND ( d = ? ) ) ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` = ? AND `b` = ?  ) OR ( `c` = ? AND `d` = ? )',
              bind   => ((a => 'a'), (b => 'b'), ( c => 'c'),( d => 'd')),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => ( { a => 1, b => 1}, ( a => 2, b => 2) ) ),
              stmt   => 'SELECT * FROM test WHERE ( ( ( ( ( a = ? ) AND ( b = ? ) ) ) OR ( ( ( a = ? ) OR ( b = ? ) ) ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` = ? AND `b` = ? ) OR ( `a` = ? OR `b` = ? )',
              bind   => ((a => 1), (b => 1), ( a => 2), ( b => 2)),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => ( ( a => 1, b => 1), { a => 2, b => 2 } ) ),
              stmt   => 'SELECT * FROM test WHERE ( ( ( ( ( a = ? ) OR ( b = ? ) ) ) OR ( ( ( a = ? ) AND ( b = ? ) ) ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` = ? OR `b` = ? ) OR ( `a` = ? AND `b` = ? )',
              bind   => ((a => 1), (b => 1), ( a => 2), ( b => 2)),
      },
      {
              func   => 'insert',
              args   => \('test', (qw/1 2 3 4 5/), returning => 'id' ),
              stmt   => 'INSERT INTO test VALUES (?, ?, ?, ?, ?) RETURNING id',
              stmt_q => 'INSERT INTO `test` VALUES (?, ?, ?, ?, ?) RETURNING `id`',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'insert',
              args   => \('test', (qw/1 2 3 4 5/), returning => 'id, foo, bar' ),
              stmt   => 'INSERT INTO test VALUES (?, ?, ?, ?, ?) RETURNING id, foo, bar',
              stmt_q => 'INSERT INTO `test` VALUES (?, ?, ?, ?, ?) RETURNING `id, foo, bar`',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'insert',
              args   => \('test', (qw/1 2 3 4 5/), returning => (<id  foo  bar> ) ),
              stmt   => 'INSERT INTO test VALUES (?, ?, ?, ?, ?) RETURNING id, foo, bar',
              stmt_q => 'INSERT INTO `test` VALUES (?, ?, ?, ?, ?) RETURNING `id`, `foo`, `bar`',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'insert',
              args   => \('test', (qw/1 2 3 4 5/),  returning => 'id, foo, bar' ),
              stmt   => 'INSERT INTO test VALUES (?, ?, ?, ?, ?) RETURNING id, foo, bar',
              stmt_q => 'INSERT INTO `test` VALUES (?, ?, ?, ?, ?) RETURNING id, foo, bar',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'insert',
              args   => \('test', (qw/1 2 3 4 5/),  returning => 'id' ),
              stmt   => 'INSERT INTO test VALUES (?, ?, ?, ?, ?) RETURNING id',
              stmt_q => 'INSERT INTO `test` VALUES (?, ?, ?, ?, ?) RETURNING id',
              bind   => (qw/1 2 3 4 5/),
      },
      {
              func   => 'select',
              new    => {bindtype => 'columns'},
              args   => \('test', '*', where => ( Y => { '=' => { -max => { -LENGTH => { -min => 'x' } } } } ) ),
              stmt   => 'SELECT * FROM test WHERE ( Y = (MAX (LENGTH (MIN ?))) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `Y` = ( MAX( LENGTH( MIN ? ) ) ) )',
              bind   => ((Y => 'x')),
      },
      {
              func => 'select',
              args => \('test', '*', where => { a => { '=' => Any }, b => { -is => Any }, c => { -like => Any } }),
              stmt => 'SELECT * FROM test WHERE ( ( ( a IS NULL ) AND ( b IS NULL ) AND ( c IS NULL ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` IS NULL AND `b` IS NULL AND `c` IS NULL )',
              bind => (),
      },
      {
              func => 'select',
              args => \('test', '*', where => { a => { '!=' => Any }, b => { -is_not => Any }, c => { -not_like => Any } }),
              stmt => 'SELECT * FROM test WHERE ( ( ( a IS NOT NULL ) AND ( b IS NOT NULL ) AND ( c IS NOT NULL ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` IS NOT  NULL AND `b` IS NOT  NULL AND `c` IS NOT  NULL )',
              bind => (),
      },
      {
              func => 'select',
              args => \('test', '*', where => { a => { IS => Any }, b => { LIKE => Any } }),
              stmt => 'SELECT * FROM test WHERE ( ( ( a IS NULL ) AND ( b IS NULL ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` IS NULL AND `b` IS NULL )',
              bind => (),
      },
      {
              func => 'select',
              args => \('test', '*', where =>{ a => { 'IS NOT' => Any }, b => { 'NOT LIKE' => Any } }),
              stmt => 'SELECT * FROM test WHERE ( ( ( a IS NOT NULL ) AND ( b IS NOT NULL ) ) )',
              stmt_q => 'SELECT * FROM `test` WHERE ( `a` IS NOT  NULL AND `b` IS NOT  NULL )',
              bind => (),
      },
      {
              func => 'select',
              args => ('`test``table`', ('`test``column`')),
              stmt => 'SELECT `test``column` FROM `test``table`',
              stmt_q => 'SELECT ```test````column``` FROM ```test````table```',
              bind => (),
      },
      {
              func => 'select',
              args => ('`test\\`table`', ('`test`\\column`')),
              stmt => 'SELECT `test`\column` FROM `test\`table`',
              stmt_q => 'SELECT `\`test\`\\\\column\`` FROM `\`test\\\\\`table\``',
              esc  => '\\',
              bind => (),
      },
      {
              func => 'update',
              args => \('mytable', { foo => 42 }, where => { baz => 32 }, returning => 'id' ),
              stmt => 'UPDATE mytable SET foo = ? WHERE ( baz = ? ) RETURNING id',
              stmt_q => 'UPDATE `mytable` SET `foo` = ? WHERE `baz` = ? RETURNING `id`',
              bind => (42, 32),
      },
      {
              func => 'update',
              args => \('mytable', { foo => 42 }, where => { baz => 32 }, returning => '*' ),
              stmt => 'UPDATE mytable SET foo = ? WHERE ( baz = ? ) RETURNING *',
              stmt_q => 'UPDATE `mytable` SET `foo` = ? WHERE `baz` = ? RETURNING *',
              bind => (42, 32),
      },
      {
              func => 'update',
              args => \('mytable', { foo => 42 }, where => { baz => 32 }, returning => ('id','created_at') ),
              stmt => 'UPDATE mytable SET foo = ? WHERE ( baz = ? ) RETURNING id, created_at',
              stmt_q => 'UPDATE `mytable` SET `foo` = ? WHERE `baz` = ? RETURNING `id`, `created_at`',
              bind => (42, 32),
      };


multi sub MAIN(Bool :$debug, Int :$from, Int :$to, Int :$only) {

    my $range;
    if $from.defined && $to.defined {
        $range = $from .. $to;
    }
    else {
        $range = $only // $from // $to // ^(@tests.elems);
    }

    say $range;

my $s = Squirrel.new(:$debug);

for @tests[$range.list] -> $test {
    diag $++;
    my $args = $test<args>;
    my @res;
    next unless $test<stmt>;
    my $meth = $test<func>;
    my $obj = do if $test<new> -> $args {
        Squirrel.new(|$args, :$debug);
    }
    else {
        $s;
    }
#     lives-ok {
        @res = $obj."$meth"(|$args);
#        }, "$meth";
    is @res[0], $test<stmt>, "$meth SQL looks good";
    my @bind = $test<bind>.map(-> $v { if not $v.defined { $v } else { my $t = $v ~~ Int ?? $v !! $v ~~ Str ?? val($v) !! $v; given $t { when Numeric { +$_ }; when Str { $_.Str }; default { $_ }}}});
    is-deeply @res[1].Array, @bind.Array, "bind values ok";
}


done-testing;
}
# vim: expandtab shiftwidth=4 ft=perl6
