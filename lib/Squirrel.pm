use v6;

=begin pod

=head1 NAME

Squirrel -  sql generator


=head1 SYNOPSIS

=begin code

use Squirrel;

my $s = Squirrel.new;

my ($sql, @bind) = $s.select('foo', *, where => bar => 3); # "select * from foo where bar = ?", [3];

=end code

=head1 DESCRIPTION


=head1 METHODS



=end pod

class Squirrel {

    role FallbackRHS { }

    role LiteralValue { }


    subset Logic of Str where { $_.defined && $_.uc ~~ "OR"|"AND" };

    has Bool  $.array-datatypes;
    has Str   $.case where 'lower'|'upper' = 'upper';
    has Logic $.logic = 'AND';
    has Str   $.bindtype = 'normal';
    has Str   $.cmp = '=';

    method config() {
        { :$!array-datatypes, :$!case, :$!logic, :$!bindtype, :$!cmp }
    }

    role Clause {
        has Bool $.debug = False;

        method debug(*@args) {
            if $*SQUIRREL-DEBUG || $!debug {
                note "[{ callframe(3).code.?name }] ", @args;
            }
        }
        has $.convert;
        has $.array-datatypes;
        has Str $.case where 'lower'|'upper' = 'upper';
        has Logic $.logic = 'AND';
        has Str $.bindtype = 'normal';
        has Str $.cmp = '=';

        has Str $.sql;
        has     @.bind;

        has Regex $.equality-op   = do { my $cmp = $!cmp; rx:i/^( $cmp | \= )$/ };
        has Regex $.inequality-op = rx:i/^( '!=' | '<>' )$/;
        has Regex $.like-op       = rx:i/^ (is\s+)? r?like $/;
        has Regex $.not-like-op   = rx:i/^ (is\s+)? not \s+ r?like $/;
        has Str $.sqltrue   = '1=1';
        has Str $.sqlfalse  = '0=1';

        has Regex $.injection-guard = rx:i/ \; | ^ \s* go \s /;

        multi submethod TWEAK() {
            $!case     //= 'upper';
            $!logic    //= 'AND';
            $!bindtype //= 'normal';
            $!cmp      //= '=';
            $!injection-guard //= rx:i/ \; | ^ \s* go \s /;
            $!equality-op   //= do { my $cmp = $!cmp; rx:i/^( $cmp | \= )$/ };
            $!inequality-op //= rx:i/^( '!=' | '<>' )$/;
            $!like-op       //= rx:i/^ (is\s+)? r?like $/;
            $!not-like-op   //= rx:i/^ (is\s+)? not \s+ r?like $/;
            $!sqltrue   //= '1=1';
            $!sqlfalse  //= '0=1';
        }

        method Str() returns Str {
            # Call the method 
            self.sql;
        }
        method sqlcase(Str:D $sql) returns Str {
            ($!case.defined && $!case eq 'lower' ) ?? $sql.lc !! $sql.uc;
        }
        proto method quote(|c) { * }

        multi method quote(LiteralValue $label) returns LiteralValue {
            $label;
        }
        multi method quote(Str $label) returns Str {
            $label;
        }

        multi method quote(Whatever $) {
            self.quote: '*';
        }

        multi method quote('*') {
            '*';
        }

        multi method quote(Any:U $) {
            ''
        }

        multi method convert($arg, Bool :$quote = False) {
            my $convert-arg = $quote ?? self.quote($arg) !! $arg;
            if $!convert {
                self.sqlcase($!convert ~'(' ~ $convert-arg ~ ')');
            }
            else {
                $convert-arg;
            }
        }

        proto method parenthesise(|c) { * }
        # Almost certainly didn't get a whole expression
        multi method parenthesise(Str $key, FallbackRHS $sql) returns Str {
            $sql;
        }
        multi method parenthesise(Str $key, Str $sql where * !~~ FallbackRHS) returns Str {
            self.debug("got nested func { $*NESTED-FUNC-LHS // '<none>' } and LHS $key - clause $sql");
            $*NESTED-FUNC-LHS && ($*NESTED-FUNC-LHS eq $key) ?? $sql !! "( $sql )";
        }

        multi method parenthesise(Str $key, Clause $sql) returns Str {
            self.parenthesise: $key, $sql.sql;
        }

        method apply-bindtype(Str $column, $values) {
            self.debug("Column { $column // <undefined> } - with bindtype { $!bindtype // '<none>' } and { $values.perl }");
            given $!bindtype {
                when 'columns' {
                    if $!array-datatypes {
                        self.debug($values.WHAT);
                        ($column => $values.elems > 1 ?? $values.list !! $values[0] )
                    }
                    else {
                        $values.map(-> $v { $column => $v });
                    }
                }
                default {
                    self.debug("default bind-type");
                    $!array-datatypes ?? $values.elems > 1 ?? [ $values.item ] !! $values.item !! $values;
                }
            }
        }

        my class X::InvalidBind is Exception {
            has Str $.message = "bindtype 'columns' selected, you need to pass: [column_name => bind_value]";
        }

        method assert-bindval-matches-bindtype(*@bind) {
            if $!bindtype eq 'columns' {
                for @bind -> $item {
                    self.debug("got item - { $item.perl } ");
                    if not $item.defined || $item !~~ Pair || $item.elems != 2 {
                        X::InvalidBind.new.throw;
                    }
                }
            }
        }

        my class X::Injection is Exception {
            has Str $.sql is required;
            has Str $.class is required;
            method message() returns Str {
                "Possible SQL injection attempt '{ $!sql }'. If this is indeed a part of the "
                ~ "desired SQL use literal SQL \( \'...' or \[ '...' ] \) or supply your own "
                ~ "\{injection-guard\} attribute to { $!class }.new\()"
            }
        }

        method assert-pass-injection-guard(Str $sql) {
            if $sql ~~ $!injection-guard {
                X::Injection.new(:$sql, class => self.^name).throw;
            }
        }
    }

    class SqlFalse does Clause {
        method sql(--> Str) {
            $*SQLFALSE // $!sqlfalse;
        }
    }

    sub FALSE( --> SqlFalse) is export {
        SqlFalse.new
    }

    class SqlTrue does Clause {
        method sql(--> Str) {
            $*SQLTRUE // $!sqltrue;
        }
    }

    sub TRUE( --> SqlTrue) is export {
        SqlTrue.new
    }

    class SqlLiteral does Clause does LiteralValue {
        method list() {
            [$!sql, @!bind.flat];
        }
    }

    multi sub SQL(Str $sql, *@bind) returns LiteralValue is export {
        SqlLiteral.new(:$sql, :@bind);
    }

    multi sub SQL(Str $sql) returns LiteralValue is export {
        SqlLiteral.new(:$sql);
    }


    sub is-literal-value($value) returns Bool {
        $value ~~ LiteralValue;
    }


    multi sub is-plain-value(Stringy $) returns Bool {
        True
    }

    multi sub is-plain-value(Numeric $) returns Bool {
        True
    }

    multi sub is-plain-value($) returns Bool {
        False;
    }

    class Expression does Clause {

    }

    class ExpressionGroup does Clause {
        has Clause @.clauses handles <append>;
        has Bool $.inner is rw;
        proto method join-sql-clauses(|c) { * }

        multi method join-sql-clauses(Str:D $logic, @clauses where *.elems > 1, $bind is copy where *.elems > 0 ) {
            self.debug("joining { @clauses.perl } with bind { $bind.^name }");
            my $join = " " ~ self.sqlcase($logic) ~ " ";
            my $sql = '( ' ~ @clauses.map({ "( $_ )" }).join($join) ~ ' )';
            ($sql, $bind );
        }
        multi method join-sql-clauses(Str:D $logic, @clauses where *.elems > 1, $bind is copy where *.elems == 0 ) {
            self.debug("joining { @clauses.perl } with no bind ");
            my $join = " " ~ self.sqlcase($logic) ~ " ";
            my $sql = '( ' ~ @clauses.map({ "( $_ )" }).join($join) ~ ' )';
            ($sql, Empty );
        }

        multi method join-sql-clauses(Str:D $logic, @clauses where *.elems == 1, $bind is copy) {
            self.debug("joining just the one clause and bind { $bind.perl }");
            (@clauses[0], $bind);
        }

        multi method join-sql-clauses(Str:D $logic, @clauses where *.elems == 0, @bind) {
            Empty
        }

        method bind() {
            my @bind;
            for @!clauses -> $clause {
                @bind.append: $clause.bind;
            }
            @bind;
        }


        method sql(Bool :$outer, Bool :$inner = $!inner) returns Str {
            my $join = " " ~ self.sqlcase($!logic) ~ " ";
            my $sql = @!clauses.map(-> $v { $v.sql } ).join($join);
            (!$outer && $inner) ?? "( $sql )" !! $sql;
        }
    }


    role Statement does Clause {
    }

    role Operators {

        proto method build-expression(|c) { * }

        my subset FallbackOp of Str:D where { $_ !~~ m:i/(bool|and|or|ident|nest|value)/ };

        multi method unary-op(Str $op where /^'-'/, $rhs) returns Clause {
            self.debug("got op $op - trimming");
            self.unary-op: $op.substr(1), $rhs;
        }

        multi method unary-op(FallbackOp $op, $rhs where Stringy|Numeric) returns Clause {
            self.debug("got $op and $rhs");
            self.assert-pass-injection-guard($op);
            my $sql = sprintf "%s %s", self.sqlcase($op), self.convert('?');
            $sql does FallbackRHS;
            my @bind = self.apply-bindtype($*NESTED-FUNC-LHS // $op, $rhs);
            Expression.new(:$sql, :@bind);
        }

        multi method unary-op(FallbackOp $op, $rhs) returns Clause {
            self.debug("with $op and { $rhs.perl }");
            my $clause = self.build-expression($rhs);
            Expression.new(sql => (sprintf '%s %s', self.sqlcase($op), $clause.sql(:inner)), bind => $clause.bind);
        }
     
     
         # not really enhancing the reputation with regard to the line-noise thing 
        multi method unary-op(Str $op where /:i^ and  ( [_\s]? \d+ )? $/|/:i^ or   ( [_\s]? \d+ )? $/,  @value) returns Clause {
            self.debug("array with $op");
            self.build-expression(@value, logic => $op, :inner);
        }
     
        multi method unary-op(Str:D $op where /:i^ or   ( [_\s]? \d+ )? $/, %value) returns Clause {
            self.debug("hash with $op");
            my @value = %value.pairs.sort(*.key);
            self.build-expression(@value, logic => $op, :inner);
        }
     
         multi method unary-op(Str:D $op where /:i^ and  ( [_\s]? \d+ )? $/, %value) returns Clause {
            self.debug("hash with $op");
             self.build-expression(%value, :inner);
         }
     
         multi method unary-op(Str $op where /:i^ nest ( [_\s]? \d+ )? $/, Str:D $value) returns Clause {
             Expression.new(sql => $value);
         }
         
         multi method unary-op(Str $op where /:i^ nest ( [_\s]? \d+ )? $/, $value) returns Clause {
             self.build-expression($value, :inner);
         }
     
         multi method unary-op(Str:D $op where /:i^  bool   $/, Str:D $value) returns Clause {
             self.debug("bool with Str $value");
             Expression.new(sql => self.convert(self.quote($value)));
         }
     
         multi method unary-op(Str:D $op where /:i^ bool     $/, $value) returns Clause {
             self.debug("bool with other $value");
             self.build-expression($value);
         }
     
         multi method unary-op(Str:D $op where m:i/^ ( not \s ) bool     $/, $value) returns Clause {
             my $clause = self.unary-op: 'bool', $value;
             Expression.new(sql => "NOT " ~ $clause.sql(:inner), bind => $clause.bind);
         }
     
        # Equality expression
         multi method unary-op(Str $op where m:i/^ ident                  $/, Cool $lhs, Cool $rhs) returns Clause {
             Expression.new( sql => self.convert(self.quote($lhs)) ~ " = " ~ self.convert(self.quote($rhs)));
         }
     
         
        # Null Expression
         multi method unary-op(Str $op where m:i/^ value                  $/, Cool $lhs, Cool:U $rhs?) returns Clause {
             defined $lhs ?? Expression.new(sql => self.convert(self.quote($lhs)) ~ ' IS NULL') !! Expression;
         }
     
        # Equality Expression with bind;
         multi method unary-op(Str $op where m:i/^ value                  $/, Cool $lhs, Cool:D $rhs) returns Clause {
             my @bind = self.apply-bindtype( $lhs.defined ?? $lhs !! $*NESTED-FUNC-LHS // Any, $rhs).flat;
             my $sql = $lhs ?? self.convert(self.quote($lhs)) ~ ' = ' ~ self.convert('?') !! self.convert('?');
             Expression.new(:$sql, :@bind);
         }
    }



    has Str $.sqltrue   = '1=1';
    has Str $.sqlfalse  = '0=1';
    has Regex $.injection-guard = rx:i/ \; | ^ \s* go \s /;

    has $.quote-char;

    method quote-chars() {
        given $!quote-char.elems {
            when 1 {
                ($!quote-char, $!quote-char);
            }
            when 2 {
                $!quote-char.list;
            }
        }
    }


    class Returning does Clause {

        has $.fields;

        proto method sql(|c) { * }

        multi method sql() returns Str {
            self.sqlcase('returning') ~ ' ' ~ $!fields.map(-> $v { self.quote($v) }).join(', ');
        }
    }




    class InsertValues does Clause {
        has Clause @.clauses;
        has Str @.fields;

        method sql() returns Str {
            $!sql //= ( self.field-list.defined ?? self.field-list ~ ' ' !! '' ) 
                      ~ self.sqlcase('values') ~ ' ( ' ~ @!clauses.map({ $_.sql }).join(', ') ~ ' )';

        }

        method bind() {
            self.debug("getting bind");
            @!clauses.flatmap({ $_.bind });
        }

        method field-list() returns Str {
            my Str $fields;
            if @!fields.elems > 0 {
                $fields = '( ' ~ @!fields.join(', ') ~ ' )';
            }
            $fields;
        }
    }

    class Insert does Statement {

        has Str $.table;

        has Clause $.clauses;
        has Returning $.returning;

        has $.data;

        method clauses() returns Clause {
            $!clauses //= self.build-insert();
        }

        method bind() {
            self.clauses.bind;
        }


        proto method build-insert(|c) { * }

        multi method build-insert() returns Clause {
            self.build-insert($!data);
        }

        multi method build-insert(%data) returns Clause {
            self.debug('Hash');
            self.insert-values(%data);
        }

        class X::InvalidBindType is Exception {
            has Str $.message;
        }

        multi method build-insert(@data) returns Clause {
            self.debug("Array");

            if $!bindtype eq 'columns' {
                X::InvalidBindType.new(message => "can't do 'columns' bindtype when called with arrayref").throw;
            }

            # TODO: pass on the config
            my $iv = InsertValues.new;

            for @data -> $value {
                $iv.clauses.append: self.insert-value(Str, $value);
            }
            $iv;
        }



        multi method build-insert(Clause $data ) returns Clause {
            self.assert-bindval-matches-bindtype($data.bind);
            $data;
        }


        multi method build-insert(Str $data) returns Clause {
            flat ($data, Empty);
        }

        method insert-values(%data) returns Clause {


            my $iv = InsertValues.new;
            for %data.pairs.sort(*.key) -> $p {
                $iv.fields.append: $p.key;
                $iv.clauses.append: self.insert-value($p);
            }

            $iv;
        }

        proto method insert-value(|c) { * }

        multi method insert-value(Pair $p) returns Clause {
            self.debug("pair");
            self.insert-value($p.key, $p.value);
        }

        class Placeholder does Clause {
            method sql() returns Str {
                '?'
            }
        }
        multi method insert-value(Str $column, @value ) returns Clause {
            self.debug("array value { @value.perl }");
            my (@values, @all-bind);
            if $!array-datatypes {
                Placeholder.new(bind => self.apply-bindtype($column, @value));
            }
            else {
                my ( $sql, @bind) = @value;
                self.assert-bindval-matches-bindtype(@bind);
                @values.append: $sql;
                @all-bind.append: @bind;
            }
        }

        multi method insert-value(Str $column, %value) returns Clause {
            self.debug("hash value");
            my (@values, @all-bind);
            Placeholder.new(bind => self.apply-bindtype($column, %value).flat);
        }

        multi method insert-value(Str $column, $value where { $_ !~~ SqlLiteral }) returns Clause {
            self.debug("plain value { $value // '<undefined>' }");
            my $v = do if $value ~~ Str {
                my $a = val($value);
                if $a ~~ Numeric {
                    +$a;
                }
                else {
                    $value;
                }
            }
            else {
                $value
            }
            Placeholder.new(bind => self.apply-bindtype($column, $v));
        }

        multi method insert-value(Str $column, SqlLiteral $value ) returns Clause {
            $value;
        }

        method sql() returns Str {
            my $sql = (self.sqlcase('insert into'), self.table, self.clauses.sql).join(" ");
            $sql ~= ' ' ~ $!returning.sql if $!returning;
            $sql;
        }
    }

    method insert($table, $data, :$returning) {

        my %args = (:$table, :$data, |self.config);



        if $returning {
            %args<returning> = Returning.new(fields => $returning, |self.config);
        }

        Insert.new(|%args);
    }

 
    class Where does Statement does Operators {
        has Clause $.clause;
        has $.where;

        method sql() returns Str {
            $!sql //= self.sqlcase('WHERE') ~ " " ~ self.clause.sql(:outer);
        }

        multi method new(Any:U $) {
            self.debug("no where");
            self.bless();
        }
     

        method clause() returns Clause handles <bind> {
            $!clause //= self.build-expression($!where);
        }
     
        proto method build-expression(|c) { * }
     
     
        multi method build-expression(Bool $ where { $_ == Bool::False }, $logic? --> Clause) {
            SqlFalse.new;
        }
        multi method build-expression(Bool $ where { $_ == Bool::True }, $logic? --> Clause) {
            SqlTrue.new;
        }
        multi method build-expression(@where, Any:U $logic?) returns Clause {
            self.build-expression: @where, :$!logic;
        }
     
        multi method build-expression(@where, Logic $logic) returns Clause {
            self.build-expression: @where, :$logic;
        }
     
        multi method build-expression(@where, Logic :$logic = 'OR', Bool :$inner) returns Clause {
             my @clauses = @where;
             self.debug("(Array) got clauses { @where.perl } with $logic");
     
             my ExpressionGroup $clauses = ExpressionGroup.new(:$logic, :$inner, :$!case);
             while @clauses.elems {
                 my $el = @clauses.shift;
     
                 my Clause $sub-clause = do given $el {
                     when Positional {
                         self.debug("positional clause");
                         self.build-expression($el, :$logic, :inner);
                     }
                     when Associative|Pair {
                         self.debug("pair clause { $el.perl }");
                         next unless $el.keys.elems; # Skip empty
                         self.build-expression($el, logic => 'and', :inner);
                     }
                     when Str {
                         self.debug("Str clause");
                         self.build-expression($el => @clauses.shift, :$logic);
                     }
                     default {
                         self.debug("fallback with { $el.perl } and logic ($logic)");
                         self.build-expression($el, :$logic);
                     }
                 }

                 $clauses.clauses.append: $sub-clause;
             }
             $clauses;
        }
     
     
         multi method build-expression(Logic :$logic, *%where) {
             self.debug("slurpy hash");
             self.build-expression: %where, :$logic;
         }
     
         multi method build-expression($where, Logic :$logic) {
             self.debug("Dumb with { $where.perl }");
             Expression.new(sql => $where);
         }
     
        # Awful
        multi method build-expression($where) {
            self.debug("Fallback with { $where.perl }");
            self.build-expression: $where, logic => ( $where ~~ Positional ?? 'OR' !! 'AND'), inner => False;
        }

        multi method build-expression(%where where * !~~ Pair, Logic :$logic, Bool :$inner) returns Clause {
     
            my ExpressionGroup $clauses = ExpressionGroup.new(:$logic, :$inner, :$!case);
            self.debug("hash -> { %where.perl } with $logic ");
     
            my Bool $inner-inner = $inner || %where.pairs.elems > 1;
            for %where.pairs.sort(*.key) -> Pair $pair {
                self.debug("got pair { $pair.perl } ");
                my Clause $sub-clause = self.build-expression($pair, inner => $inner-inner);
                $clauses.append: $sub-clause;
            }
            $clauses;
         }
     
         role LiteralPair does Clause {
         }
     
         multi method build-expression(Pair $p where * !~~ LiteralPair ( Str :$key where * ~~ /^\-./, :$value)) returns Clause {
             my $op = $key.substr(1).trim.subst(/^not_/, 'NOT ', :i);
             self.debug("Pair not Literal but Key is $key (op is $op)");
             self.unary-op($op, $value);
         }

         multi method build-expression(Pair $p ( Str :$key, :$value where Stringy|Numeric )) returns Clause {
             self.debug("Pair with Stringy|Numeric value");
            # TODO: Equality expression
             Expression.new(sql => "$key { self.sqlcase($!cmp // '=') } ?", bind => self.apply-bindtype($key, $value));
         }
     
     
         multi method build-expression(Pair $p where * !~~ LiteralPair ( Str:D :$key where { $_  ~~ m:i/^\-[AND|OR]$/ }, :@value where *.elems > 0 )) returns Clause {
             my $new-logic = $key.substr(1).lc;
             self.debug("got a pair with an/or op will redispatch with logic $new-logic");
             self.build-expression: @value, logic => $new-logic;
         }
     
     
         multi method build-expression(Pair $p where * !~~ LiteralPair ( :$key, :@value where { $_ !~~ SqlLiteral && $_.elems > 0 }), Logic :$logic = 'OR') returns Clause {
             my @values = @value;
             self.debug("pair $key => { @values.perl } logic({ $logic // '<undefined>'})");
             self.debug($p.WHAT);
             my @distributed = @values.map(-> $v { $key => $v });
     
             self.debug("redistributing array with '{ $logic // "<undefined>" }' with a { @distributed.perl }");
             self.build-expression(@distributed, :$logic, :inner);
         }
     
         multi method build-expression(Pair $p ( :$key, :@value where *.elems == 0)) returns Clause {
             SqlFalse.new;
         }
     
         multi method build-expression(Pair $p ( :$key, Any:U :$value), Logic :$logic) returns Clause {
             Expression.new(sql => self.quote($key) ~ self.sqlcase(" is null"));
         }
     
        multi method build-expression(Pair $p ( :$key where /^'-'/, SqlLiteral :$value) ) returns Clause {
             self.debug("got pair  with SqlLiteral value { $p.perl } but op key");
             my $clause = self.unary-op($key, $value[0]);
             $clause.bind.append($value[1..*]) if $value.elems > 1;
             $clause;
        }
     
         multi method build-expression(Clause $value )  returns Clause {
             self.debug("Maybe SqlLiteral");
             $value;
         }
     
     
        multi method build-expression(Pair $p ( Str :$key, Clause :$value ), Logic :$logic, Bool :$inner ) returns Clause {
            my $sql = sprintf "%s %s", $key, $value.sql;
            Expression.new(:$sql, bind => $value.bind);
        }

         multi method build-expression(Pair $p ( :$key, Pair :$value (:key($orig-op), SqlLiteral :value($val) ) ), Logic :$logic = 'or', Bool :$inner) returns Clause {
             self.debug("Pair with SqlLiteral pair value");
             my $inner-clause = self.build-expression($value, :$logic, :$inner);
             self.build-expression($key => $inner-clause, :$logic, :$inner);
         }

         
         multi method build-expression(Pair $p ( :$key, Pair :$value (:key($orig-op), :value($val) ) ), Logic :$logic = 'or', Bool :$inner) returns Clause {
             self.debug("Pair with pair value : { $p.perl }");

             my Clause $sub-clause;
             my $op = $orig-op.subst(/^\-/,'').trim.subst(/\s+/, ' ');
             self.assert-pass-injection-guard($op);
             $op ~~ s:i/^is_not/IS NOT/;
             $op ~~ s:i/^not_/NOT /;
 
             if $orig-op ~~ m:i/^\-$<logic>=(and|or)/ {
                 self.debug("passing on the logic {  ~$/<logic> }");
                 $sub-clause = self.build-expression($key => $val, logic => ~$/<logic>);
             }
             elsif self.use-special-op($key, $op, $val) {
                 self.debug("use-special-up said yes to $key $op");
                 $sub-clause = self.special-op($key, $op, $val);
             }
             else {
                 # TODO : vigourous refactoring
                 given $val {
                     when Positional {
                         self.debug("Positional { $val.perl } trying field-op");
                         $sub-clause = self.field-op($key, $op, $val, :$inner);
                     }
                     when Any:U {
                         self.debug("NULL with $op");
                         my $is = do given $op {
                             when $.equality-op|$.like-op {
                                 'is'
                             }
                             when $.inequality-op|$.not-like-op {
                                 'is not'
                             }
                             default {
                                 die "unexpectated operator '$op' for NULL";
                             }
                         }
                         my $sql = self.quote($key) ~ self.sqlcase(" $is null");
                        # TODO: NULL expression type
                         $sub-clause = Expression.new(sql => $sql);
                     }
                     default {
                         self.debug("default with { $val.perl }");
                         my $rhs = self.unary-op($op, $val);
                        # TODO: this should be built in to the Expression
                         my $sql = (self.convert(self.quote($key)), self.parenthesise($key, $rhs)).join(' ');
                         $sub-clause = Expression.new(:$sql, bind => $rhs.bind);
                     }
                 }
             }
             $sub-clause;
         }
         multi method build-expression(Pair $p ( :$key, :%value where { $_.keys.elems == 1}), Logic :$logic = 'or', Bool :$inner) returns Clause {
             my $*NESTED-FUNC-LHS = $key;
             self.debug("Pair with Pairish value");
             self.build-expression($key => %value.pairs.first, :$logic, :$inner);
         }
     
         multi method build-expression(Pair $p ( :$key, :%value where { $_.keys.elems > 1}), Logic :$logic = 'and', Bool :$inner) returns Clause {
             self.debug("Got a pair with a hash value");
             my $*NESTED-FUNC-LHS = $*NESTED-FUNC-LHS // $key;
     
            my ExpressionGroup $clauses = ExpressionGroup.new(:$logic, :$inner, :$!case);

             for %value.pairs.sort(*.key) -> $pair (:key($orig-op), :value($val)) {
                 self.debug("pair { $orig-op => $val.perl }");
                 my Clause $sub-clause = self.build-expression($key => $pair, :$logic);
     
                $clauses.clauses.append: $sub-clause;
             }
             $clauses;
         }
     
         method use-special-op($key, $op, $value) {
             ?self.^lookup('special-op').cando(Capture.from-args(self, $key, $op, $value))
         }
     
         proto method special-op(|c) { * }
     
         class X::IllegalOperator is Exception {
             has Str $.op is required;
             method message() returns Str {
                 "Illegal use of top level '-{ $!op }'";
             }
         }
     
    
     
     
     
         multi method special-op(Str $key, Str $op where /:i^ is ( \s+ not )?     $/, Any:U $) returns Clause {
             Expression.new(sql => (self.convert(self.quote($key)), ($op, 'null').map(-> $v { self.sqlcase($v) })).join(' '));
     
         }
     
         proto method field-op(|c) { * }
     
         multi method field-op(Str $key, Str $op, @vals where *.elems > 0, Bool :$inner) returns Clause {
             my @values  = @vals;
             my $logic = 'or';
             if @values[0].defined && @values[0] ~~ m:i/^ \- $<logic>=( AND|OR ) $/ {
                 $logic = $/<logic>.Str.uc;
                 @values.shift;
             }
             ExpressionGroup.new(clauses =>self.build-expression(@values.map( -> $v { $key => $op =>  $v }), $logic), :$logic, :$inner, :$!case);
         }
     
         multi method field-op(Str $key, Str:D $op where $!equality-op, @values where *.elems == 0, Bool :$inner) returns Clause {
             SqlFalse.new;
         }
     
         multi method field-op(Str $key, Str:D $op where $!inequality-op, @values where *.elems == 0, Bool :$inner) {
             SqlTrue.new;
         }
     
     
     
         # BETWEEN

        class Between does Clause {
            has Clause $.lhs is required;
            has Clause $.rhs is required;
            has Str    $.op  = 'BETWEEN'; # fix case
            has Str    $.label is required;
            has Str    $.and = 'AND'; # fix case;



            method sql() returns Str {
                $!sql //= "( { $!label } { $!op } { $!lhs.sql } { $!and } { $!rhs.sql } )";
            }

            method bind() {
                my @bind;
                @bind.append: $!lhs.bind;
                @bind.append: $!rhs.bind;
                @bind;
            }
        }

        multi method special-op(Str $key, Str $op is copy where /:i^ ( not \s )? between $/, @values ($left, $right) ) returns Clause {
            self.debug("between with { @values.perl }");
            my $label           = self.convert($key, :quote);
            my $and             = self.sqlcase('and');
            $op                 = self.sqlcase($op);
    
            
            my $lhs = self.expressionise($key, $left);
            my $rhs = self.expressionise($key, $right);
            Between.new(:$lhs, :$rhs, :$label, :$op, :$and);
        }

        proto method expressionise(|c) { * }

        multi method expressionise(Str $key, Cool $value --> Expression) {
            my $placeholder     = self.convert('?');
            Expression.new(sql => $placeholder, bind => self.apply-bindtype($key, $value).flat);
        }

        multi method expressionise(Str $, Pair $ ( :$key, :$value ) --> Expression) {
            my $func = $key.subst(/^\-/,'');
            self.unary-op($func => $value);
        }
     
     
        multi sub sql-literal(@l) {
            @l but SqlLiteral
        }
    
        multi sub sql-literal(+@l) {
            @l but SqlLiteral
        }
    
        multi sub sql-literal($l) {
            $l but SqlLiteral
        }
    
        multi method special-op(Str $key, Str $op where /:i^ ( not \s )? in      $/, *@values) returns Clause {
            self.special-op: $key, $op, @values;
        }
     
        class In does Clause {
            has Str $.label is required;
            has Str $.op = "IN"; # fix case;
            has Clause @.clauses;


            method sql() returns Str {
                $!sql //= sprintf('%s %s ( %s )', $!label, $!op, @!clauses.map({ $_.sql }).join(', '));
            }
            method bind() {
                my @all-bind;
                for @!clauses -> $c {
                    @all-bind.append: $c.bind;
                }
                self.apply-bindtype($!label, @all-bind).flat;
            }
        }

        multi method special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, @values where { $_ !~~ SqlLiteral && $_.elems > 0 }) returns Clause {
            self.debug("Literal") if @values ~~ SqlLiteral;
            self.debug("KEY: $key OP : $op  VALUES { @values.perl }");
            my $label       = self.convert($key, :quote);
            my $placeholder = self.convert('?');
            $op             = self.sqlcase($op);
    
            my @clauses;
    
            for @values -> $value {
                my $sub-clause = do given $value {
                    when SqlLiteral {
                        my ($sql, @bind) = $value.list;
                        self.assert-bindval-matches-bindtype(@bind);
                        Expression.new(:$sql, :@bind);
                    }
                    when Stringy|Numeric {
                        Expression.new(sql => $placeholder, bind => $value);
                    }
                    when Pair {
                        self.debug("pair { $value.perl }");
                        self.unary-op($value).flat;
                    }
    
                }
                @clauses.append: $sub-clause;
            }

            In.new(:$op, :$label, :@clauses);
        }
    
        multi method special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, @values where *.elems == 0) returns Clause {
            $op ~~ m:i/<|w>not<|w>/ ?? SqlTrue.new !! SqlFalse.new;
        }
    
        multi method special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, SqlLiteral $values ) returns Clause {
            my $label       = self.convert($key, :quote);
            $op             = self.sqlcase($op);
            my ( $sql, @bind) = $values.list;
            self.assert-bindval-matches-bindtype(@bind);
            $sql = self.open-outer-paren($sql);
            Expression.new(sql => "$label $op ( $sql )", :@bind);
        }

        method open-outer-paren(Str $sql is copy) {
            self.debug("got $sql");
            while $sql ~~ /^ \s* \( $<inner>=(.*) \) \s* $/ -> $inner {
                if ~$inner<inner> ~~ /\)/ {
                    # do something clever with extract_bracketed
                }
                $sql = ~$inner<inner>
            }
            $sql;
        }
    }

    class UpdateSet does Clause {
        has Clause @.items handles <append>;

        method sql() returns Str {
            $!sql //= @!items.map({ $_.sql }).join(', ');
        }

        method bind() {
            @!items.flatmap({ $_.bind });
        }
    }

    class Update does Statement does Operators {

        has UpdateSet   $.clauses;
        has Where       $.where;
        has Returning   $.returning;
        has Str         $.table;

        has             $.data;

        method clauses() returns Clause {
            $!clauses //= do {
                my $clauses = UpdateSet.new;
                for $!data.pairs.sort(*.key) -> $p {
                    self.debug("Got pair { $p.perl }");
                    my $s = self.build-update($p);
                    $clauses.append: $s;
                }
                $clauses;
            }
        }

        method sql() returns Str {
            my $sql = ( self.sqlcase('update'), $.table, self.sqlcase('set'), self.clauses.sql ).join(' ');
            $sql ~= ' ' ~ $!where.sql if $!where.defined;
            $sql ~= ' ' ~ $!returning.sql if $!returning.defined;
            $sql;
        }

        method bind() {
            my @bind;
            @bind.append: self.clauses.bind;
            @bind.append: $!where.bind if $!where.defined;
            @bind;
        }

        proto method build-update(|c) { * }

        multi method build-update(Pair $p) returns Clause {
            self.debug("expanding pair { $p.perl }");
            self.build-update($p.key, $p.value.list);
        }

        multi method build-update(Pair $p (Str :$key, :%value)) returns Clause {
            self.debug("Pair with Associative value");
            self.build-update($key, %value.pairs.first);
        }


        multi method build-update(Pair $p (Str :$key, SqlLiteral :$value )) returns Clause {
            self.debug($value.sql);
            my $label = self.quote($key);
            Expression.new(sql => "$label { $!cmp } { $value.sql }", bind => $value.bind);
        }

        multi method build-update(Str $key, @values ) {
            self.debug("got values { @values.perl }");
            my $label = self.quote($key);
            my $expr;
            if @values.elems == 1 or $!array-datatypes {
                $expr = Expression.new(sql => "$label = ?", bind => self.apply-bindtype($key, @values).flat);
            }
            else { 
                my ($sql, @bind) = @values;
                self.assert-bindval-matches-bindtype(@bind);
                $expr = Expression.new(:$sql, :@bind);
            }
            $expr;
        }


        class X::InvalidOperator is Exception {
            has $.message = "Not a valid operator";
        }

        class UpdateExpression does Clause {
            has Str $.label;
            has Clause $.rhs handles <bind>;

            method sql() returns Str {
                sprintf "%s = %s", $!label, $!rhs.sql;
            }
        }

        multi method build-update(Str $key, Pair $p) returns Clause {
            self.debug("got $key with Pair { $p.perl }");
            my $*NESTED-FUNC-LHS = $key;
            my $expression;
            if $p.key ~~ /^\-$<op>=(.+)/ { 
                my $label = self.quote($key);
                my Clause $rhs = self.unary-op(~$/<op>, $p.value);
                $expression = UpdateExpression.new(:$label, :$rhs);
            }
            else {
                X::InvalidOperator.new.throw;
            }
            $expression;
        }
    }


    method update(Str $table, %data, :$where, :$returning) {

        my %args = :$table, :%data, |self.config;

        if $where {
            %args<where> = Where.new(:$where, |self.config);
        }

        if $returning {
            %args<returning> = Returning.new(fields => $returning, |self.config);
        }

        Update.new(|%args);
    }





    # Transitional
    method where(|c) {
        my $w = Where.new(|c);
        ($w.sql, $w.bind);
    }

    class OrderBy does Statement {
        has @.fields;

        has $.order;

        method sql() returns Str {
            $!sql //= self.order-by;
        }

        method order-by() {
            my (@sql, @bind);
            for self.order-by-chunks($!order) -> $c {
                given $c {
                    when Str {
                        @sql.append: $c;
                    }
                    when Positional {
                        @sql.append: $c.shift;
                        @bind.append: $c.list;
                    }
                }
            }
            @sql ?? sprintf '%s %s', self.sqlcase('order by'), @sql.join(', ') !! '';
        }

        proto method order-by-chunks(|c) { * }

        multi method order-by-chunks(@args) {
            @args.map(-> $arg { self.order-by-chunks($arg) }).flat;
        }

        multi method order-by-chunks(Str $arg) {
            ( self.quote($arg) );
        }
        multi method order-by-chunks(Any:U) {
            Empty;
        }


        class X::InvalidDirection is Exception {
            has Str $.message = 'key passed to order-by must be "desc" or "asc"';
        }

        multi method order-by-chunks(Pair $arg) {
            my @ret;
            if $arg.key ~~ /^\-?$<direction>=(desc|asc)/ {
                for self.order-by-chunks($arg.value) -> $c {
                    my ($sql, @bind);
                    given $c {
                        when Str {
                            $sql = $c;
                        }
                        when Positional {
                            ($sql, @bind) = $c.list;
                        }
                    }
                    $sql = $sql ~ ' ' ~ self.sqlcase(~$/<direction>);
                    @ret.push: [ $sql, @bind];
                }
            }
            else {
                X::InvalidDirection.new.throw;
            }

            @ret;
        }
    }

    class Join does Statement {
    }

    class Select does Statement {
        has $.from;
        has $.fields;
        has Where $.where;
        has OrderBy $.order-by;
        has Join @.join;

        proto method table(|c) { * }

        multi method table(@tables) returns Str {
            @tables.map(-> $name { self.quote($name) }).join(', ');
        }

        multi method table(Str $table) returns Str {
            self.quote($table);
        }

        method from() {
            self.table($!from);
        }

        method fields() {
            $!fields.map(-> $v { self.quote($v) });
        }

        method bind() {
            $!where.defined ?? $!where.bind !! ();
        }

        method sql() returns Str {
            my $sql = (self.sqlcase('select'), self.fields.join(', '),  self.sqlcase('from'), self.from).join(' ');
            $sql ~= ' ' ~ self.where.sql if self.where;
            $sql ~= ' ' ~ self.order-by.sql if self.order-by;
            $sql;
        }

    }

    proto method select(|c) { * }

    multi method select($table, *@fields,  :$where, :$order, :$join) returns Select {
        self.select($table, @fields, :$where, :$order, :$join);
    }

    multi method select($table, @fields, :$where, :$order, :$join) returns Select {
        my %args = from => $table, fields => @fields;
        %args<where> = Where.new(:$where, |self.config) if $where;
        %args<order-by> = OrderBy.new(:$order, |self.config) if $order;
        Select.new(|%args, |self.config);
    }

    class Delete does Statement {
        has Where $.where;
        has $.table;

        method table() returns Str {
            $!table.join(', ');
        }

        method sql() returns Str {
            $!sql //= (self.sqlcase('delete from'), self.table, $!where.defined ?? $!where.sql !! '').join(' ');
        }

        method bind() {
            $!where.defined ?? $!where.bind !! ();
        }
    }

    method delete($table, :$where) {
        my %args = :$table, |self.config;

        %args<where> = Where.new(:$where, |self.config) if $where;
        Delete.new(|%args);
    }




}

# vim: expandtab shiftwidth=4 ft=perl6
