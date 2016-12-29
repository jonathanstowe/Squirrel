use v6.c;

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

    role LiteralValue { }

    role SqlLiteral does LiteralValue {
    }

    multi sub SQL($literal, *@bind) returns LiteralValue is export {
        [$literal, |@bind] but SqlLiteral
    }

    multi sub SQL($literal) returns LiteralValue is export {
        [$literal] but SqlLiteral
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

    subset Logic of Str where { $_.defined && $_.uc ~~ "OR"|"AND" };

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
        has Logic $.logic = 'OR';
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

        submethod TWEAK() {
            $!case     //= 'upper';
            $!logic    //= 'OR';
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
            samewith '*';
        }

        multi method quote('*') {
            '*';
        }

        method convert($arg, Bool :$quote = False) {
            my $convert-arg = $quote ?? self.quote($arg) !! $arg;
            if $!convert {
                self.sqlcase($!convert ~'(' ~ $convert-arg ~ ')');
            }
            else {
                $convert-arg;
            }
        }

        multi method parenthesise(Str $key, Str $sql ) returns Str {
            self.debug("got nested func { $*NESTED-FUNC-LHS // '<none>' } and LHS $key - clause $sql");
            $*NESTED-FUNC-LHS && ($*NESTED-FUNC-LHS eq $key) ?? $sql !! "( $sql )";
        }

        multi method parenthesise(Str $key, Clause $sql) returns Str {
            samewith $key, $sql.sql;
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







    method insert($table, $data, *%options) {
        my $table-name   = self.table($table);

        my ($sql, @bind) = self.build-insert($data).flat;

        $sql = (self.sqlcase('insert into'), $table-name, $sql).join(" ");

        if %options<returning> -> $returning {
            my ($s, @b) = self.returning($returning);
            $sql ~= $s;
            @bind.append(@b);
        }

        ($sql, @bind);
    }

    proto method returning(|c) { * }

    multi method returning(@returning) returns Str {
        self.sqlcase(' returning ') ~ @returning.map(-> $v { self.quote($v) }).join(', ');
    }

    multi method returning(Str $returning) returns Str {
        self.sqlcase(' returning ') ~ self.quote($returning);
    }

    class Insert does Statement {
        
        proto method build-insert(|c) { * }

        multi method build-insert(%data) {
            self.debug('Hash');

            my @fields = %data.keys.sort.map( -> $v { self.quote($v) });

            my ($sql, @bind) = self.insert-values(%data).flat;

            $sql = '(' ~ @fields.join(', ') ~ ') ' ~ $sql;
            ($sql, @bind);
        }

        class X::InvalidBindType is Exception {
            has Str $.message;
        }

        multi method build-insert(@data) {

            self.debug("Array");

            if $!bindtype eq 'columns' {
                X::InvalidBindType.new(message => "can't do 'columns' bindtype when called with arrayref").throw;
            }

            my @values;
            my @all-bind;

            for @data.flat -> $value {
                my ($values, @bind) = self.insert-value(Str, $value).flat;
                @values.append: $values;
                @all-bind.append: @bind;
            }

            my $sql = self.sqlcase('values') ~ ' (' ~ @values.join(", ") ~ ')';
            self.debug("returning ($sql, { @all-bind.perl }");
            flat ($sql, @all-bind);
        }



        multi method build-insert(SqlLiteral $data ( $sql, @bind)) {
            self.assert-bindval-matches-bindtype(@bind);
            ($sql, @bind);
        }


        multi method build-insert(Str $data) {
            flat ($data, Empty);
        }

        method insert-values(%data) {

            my (@values, @all-bind);

            for %data.pairs.sort(*.key) -> $p {
                my ($values, @bind) = self.insert-value($p);
                @values.append: $values;
                @all-bind.append: @bind;
            }
            my $sql = self.sqlcase('values') ~ ' (' ~ @values.join(", ") ~ ')';
            flat ($sql, @all-bind);
        }

        proto method insert-value(|c) { * }

        multi method insert-value(Pair $p) {
            self.debug("pair");
            (samewith $p.key, $p.value).flat;
        }

        multi method insert-value(Str $column, @value) {
            self.debug("array value { @value.perl }");
            my (@values, @all-bind);
            if $!array-datatypes {
                @values.append: '?';
                @all-bind.append: self.apply-bindtype($column, @value).flat;
            }
            else {
                my ( $sql, @bind) = @value;
                self.assert-bindval-matches-bindtype(@bind);
                @values.append: $sql;
                @all-bind.append: @bind;
            }
            (@values.join(', '), @all-bind);
        }

        multi method insert-value(Str $column, %value) {
            self.debug("hash value");
            my (@values, @all-bind);
            @values.append: '?';
            @all-bind.append: self.apply-bindtype($column, %value).flat;
            (@values.join(', '), @all-bind);
        }

        multi method insert-value(Str $column, $value) {
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
            (('?'), self.apply-bindtype($column, $v));
        }

        multi method insert-value(Str $column, SqlLiteral $value ( $sql, @bind) ) {
            ($sql, @bind);
        }
    }

    method update(Str $table, %data, :$where, *%options) {
        my $table-name = self.table($table);

        my ( @set, @all-bind);

        for %data.pairs.sort(*.key) -> $p {
            my ( $s, @b) = self.build-update($p).flat;
            @set.append: $s;
            @all-bind.append: @b;
        }
        self.debug("got @set { @set.perl }");
        my $sql = self.sqlcase('update') ~ " $table-name " ~ self.sqlcase('set ') ~ @set.join(', ');

        if $where {
            my ($where-sql, @where-bind) = self.where($where).flat;
            $sql ~= $where-sql;
            @all-bind.append: @where-bind;
        }

        if %options<returning> {
            my ($returning-sql, @returning-bind) = self.returning(%options<returning>);
            $sql ~= $returning-sql;
            @all-bind.append: @returning-bind;
        }

        ($sql, @all-bind);
    }

    class Update does Statement {
        proto method build-update(|c) { * }

        multi method build-update(Pair $p) {
            self.debug("expanding pair { $p.perl }");
            (samewith $p.key, $p.value.list).flat;
        }

        multi method build-update(Pair $p (Str :$key, :%value)) {
            self.debug("Pair with Associative value");
            (samewith $key, %value.pairs.first).flat;
        }


        multi method build-update(Pair $p (Str :$key, SqlLiteral :$value ( $sql, @bind))) {
            my $label = self.quote($key);
            ("$label { $!cmp } $sql", @bind);
        }

        multi method build-update(Str $key, @values ) {
            self.debug("got values { @values.perl }");
            my ( @set, @all-bind);
            my $label = self.quote($key);
            if @values.elems == 1 or $!array-datatypes {
                @set.append: "$label = ?";
                @all-bind.append: self.apply-bindtype($key, @values).flat;
            }
            else { 
                my ($sql, @bind) = @values;
                self.assert-bindval-matches-bindtype(@bind);
                @set.append: "$label = $sql";
                @all-bind.append: @bind;
            }
            self.debug("bind { @all-bind.perl }");
            (@set, @all-bind);
        }


        class X::InvalidOperator is Exception {
            has $.message = "Not a valid operator";
        }

        multi method build-update(Str $key, Pair $p) {
            my $*NESTED-FUNC-LHS = $key;
            my ( @set, @all-bind);
            if $p.key ~~ /^\-$<op>=(.+)/ { 
                my $label = self.quote($key);
                my ($sql, @bind) = self.where-unary-op(~$/<op>, $p.value).flat;
                @set.append: "$label = $sql";
                @all-bind.append: @bind;
            }
            else {
                X::InvalidOperator.new.throw;
            }
            ( @set, @all-bind);
        }
    }




    class Where does Statement {
        has Clause $.clause;
        has $!where;

        method sql() returns Str {
            $!sql //= self.sqlcase('WHERE') ~ " " ~ self.clause.sql(:outer);
        }

        multi method new(Any:U $) {
            self.debug("no where");
            samewith();
        }
     
        multi method new($where) {
            self.bless(:$where);
        }
        multi method new(*%where where { $_.keys !~~ any(<clause where logic>) }) {
            self.bless(:%where, logic => 'and');
        }

        multi method new(%where) {
            self.bless(:%where, logic => 'and');
        }
     
        multi method new(*@where where *.elems > 1 , *% where { $_.keys.elems == 0 })  {
            self.bless(:@where, logic => 'or');
        }

        multi submethod BUILD(Clause :$!clause!) {
            self.debug("where with clause");
        }

        multi submethod BUILD(:$!where!, :$!logic = 'OR') {
            self.debug("where { $!where.perl } ( { $!where.^name } )");
        }

        method clause() returns Clause handles <bind> {
            $!clause //= self.build-where($!where, :$!logic);
        }
     
         proto method build-where(|c) { * }
     
     
         multi method build-where(@where, Any:U $logic?) returns Clause {
             samewith @where, :$!logic;
         }
     
         multi method build-where(@where, Logic $logic) returns Clause {
             samewith @where, :$logic;
         }
     
         multi method build-where(@where, Logic :$logic = 'OR', Bool :$inner) returns Clause {
             my @clauses = @where;
             self.debug("(Array) got clauses { @where.perl } with $logic");
     
             my ExpressionGroup $clauses = ExpressionGroup.new(:$logic, :$inner);
             while @clauses.elems {
                 my $el = @clauses.shift;
     
                 my Clause $sub-clause = do given $el {
                     when Positional {
                         self.debug("positional clause");
                         self.build-where($el, :$logic, :inner);
                     }
                     when Associative|Pair {
                         self.debug("pair clause { $el.perl }");
                         next unless $el.keys.elems; # Skip empty
                         self.build-where($el, logic => 'and', :inner);
                     }
                     when Str {
                         self.debug("Str clause");
                         self.build-where($el => @clauses.shift, :$logic);
                     }
                     default {
                         self.debug("fallback with { $el.perl } and logic ($logic)");
                         self.build-where($el, :$logic);
                     }
                 }

                 $clauses.clauses.append: $sub-clause;
             }
             $clauses;
         }
     
     
         multi method build-where(Logic :$logic, *%where) {
             self.debug("slurpy hash");
             samewith %where, :$logic;
         }
     
         multi method build-where($where, Logic :$logic) {
             [$where, () ];
         }
     
        # Awful
        multi method build-where($where) {
            self.debug("Fallback with { $where.perl }");
            samewith $where, logic => ( $where ~~ Positional ?? 'OR' !! 'AND'), inner => False;
        }
        multi method build-where(%where where * !~~ Pair, Logic :$logic, Bool :$inner) returns Clause {
     
            my ExpressionGroup $clauses = ExpressionGroup.new(:$logic, :$inner);
            self.debug("hash -> { %where.perl } with $logic ");
     
            my Bool $inner-inner = $inner || %where.pairs.elems > 1;
            for %where.pairs.sort(*.key) -> Pair $pair {
                self.debug("got pair { $pair.perl } ");
                my Clause $sub-clause = self.build-where($pair, inner => $inner-inner);
                $clauses.append: $sub-clause;
            }
            $clauses;
         }
     
         role LiteralPair does SqlLiteral {
         }
     
=begin comment
         multi method build-where(Pair $p where * !~~ LiteralPair ( Str :$key where * ~~ /^\-./, Str :$value)) returns Clause {
             my $op = $key.substr(1).trim.subst(/^not_/, 'NOT ', :i);
             self.debug("Pair not Literal but Key is $key (String value $value)");
             self.where-unary-op($op, $value);
         }
=end comment
     
         multi method build-where(Pair $p where * !~~ LiteralPair ( Str :$key where * ~~ /^\-./, :$value)) returns Clause {
             my $op = $key.substr(1).trim.subst(/^not_/, 'NOT ', :i);
             self.debug("Pair not Literal but Key is $key (op is $op)");
             self.where-unary-op($op, $value);
         }


     
         multi method build-where(Pair $p ( Str :$key, :$value where Stringy|Numeric )) returns Clause {
             self.debug("Pair with Stringy|Numeric value");
            # TODO: Equality expression
             Expression.new(sql => "$key { self.sqlcase($!cmp // '=') } ?", bind => self.apply-bindtype($key, $value));
         }
     
     
         multi method build-where(Pair $p where * !~~ LiteralPair ( Str:D :$key where { $_  ~~ m:i/^\-[AND|OR]$/ }, :@value where *.elems > 0 )) returns Clause {
             my $new-logic = $key.substr(1).lc;
             self.debug("got a pair with an/or op will redispatch with logic $new-logic");
             samewith @value, logic => $new-logic;
         }
     
     
         multi method build-where(Pair $p where * !~~ LiteralPair ( :$key, :@value where { $_ !~~ SqlLiteral && $_.elems > 0 }), Logic :$logic = 'OR') returns Clause {
             my @values = @value;
             self.debug("pair $key => { @values.perl } logic({ $logic // '<undefined>'})");
             self.debug($p.WHAT);
             my @distributed = @values.map(-> $v { $key => $v });
     
             self.debug("redistributing array with '{ $logic // "<undefined>" }' with a { @distributed.perl }");
             self.build-where(@distributed, :$logic, :inner);
         }
     
         multi method build-where(Pair $p ( :$key, :@value where *.elems == 0)) returns Clause {
             Expression.new( sql => $!sqlfalse);
         }
     
         multi method build-where(Pair $p ( :$key, Any:U :$value), Logic :$logic) returns Clause {
             Expression.new(sql => self.quote($key) ~ self.sqlcase(" is null"));
         }
     
        multi method build-where(Pair $p ( :$key where /^'-'/, SqlLiteral :$value) ) returns Clause {
             self.debug("got pair  with SqlLiteral value { $p.perl } but op key");
             my $clause = self.where-unary-op($key, $value[0]);
             $clause.bind.append($value[1..*]) if $value.elems > 1;
             $clause;
        }
     
         multi method build-where(Pair $p ( :$key, SqlLiteral :$value ) ) returns Clause {
             self.debug("got pair  with SqlLiteral value { $p.perl }");
             samewith $p but LiteralPair;
         }
     
         multi method build-where(LiteralPair $p (:$key, :@value where *.elems > 1)) returns Clause {
             self.debug("Literal pair { $p.perl }");
             my $sql = @value[0];
             self.debug("Got bind from literal { @value[1..*] }");
             my $s = self.quote($key) ~ " $sql";
             Expression.new(sql => $s, bind => @value[1..*]);
         }
     
         multi method build-where(LiteralPair $p (:$key, :@value where *.elems == 1)) returns Clause {
             self.debug("Literal pair (no bind) { $p.perl }");
             my ($sql) = @value;
             my $s = self.quote($key) ~ " $sql";
             Expression.new(sql => $s);
         }
     
     
         multi method build-where(@value where { $_ ~~ SqlLiteral && $_.elems > 1 }) returns Clause {
             self.debug("SqlLiteral with more bind");
             my ($sql, $bind) = @value;
             Expression.new(sql => $sql, bind => $bind.flat);
         }
     
         multi method build-where(@value where { $_ ~~ SqlLiteral && $_.elems == 1 })  returns Clause {
             self.debug("SqlLiteral with no bind");
             my ($sql) = @value;
             Expression.new( sql => $sql);
         }
     
     
         
         multi method build-where(Pair $p ( :$key, Pair :$value (:key($orig-op), :value($val) ) ), Logic :$logic = 'or', Bool :$inner) returns Clause {
             self.debug("Pair with pair value : { $p.perl }");

             my Clause $sub-clause;
             my $op = $orig-op.subst(/^\-/,'').trim.subst(/\s+/, ' ');
             self.assert-pass-injection-guard($op);
             $op ~~ s:i/^is_not/IS NOT/;
             $op ~~ s:i/^not_/NOT /;
 
             if $orig-op ~~ m:i/^\-$<logic>=(and|or)/ {
                 self.debug("passing on the logic {  ~$/<logic> }");
                 $sub-clause = self.build-where($key => $val, logic => ~$/<logic>);
             }
             elsif self.use-special-op($key, $op, $val) {
                 self.debug("use-special-up said yes to $key $op $val");
                 $sub-clause = self.where-special-op($key, $op, $val);
             }
             else {
                 # TODO : vigourous refactoring
                 given $val {
                     when Positional {
                         $sub-clause = self.where-field-op($key, $op, $val, :$inner);
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
                         my $rhs = self.where-unary-op($op, $val);
                        # TODO: this should be built in to the Expression
                         my $sql = (self.convert(self.quote($key)), self.parenthesise($key, $rhs)).join(' ');
                         $sub-clause = Expression.new(:$sql, bind => $rhs.bind);
                     }
                 }
             }
             $sub-clause;
         }
         multi method build-where(Pair $p ( :$key, :%value where { $_.keys.elems == 1}), Logic :$logic = 'or', Bool :$inner) returns Clause {
             my $*NESTED-FUNC-LHS = $key;
             self.debug("Pair with Pairish value");
             self.build-where($key => %value.pairs.first, :$logic, :$inner);
         }
     
         multi method build-where(Pair $p ( :$key, :%value where { $_.keys.elems > 1}), Logic :$logic = 'and', Bool :$inner) returns Clause {
             self.debug("Got a pair with a hash value");
             my $*NESTED-FUNC-LHS = $*NESTED-FUNC-LHS // $key;
     
            my ExpressionGroup $clauses = ExpressionGroup.new(:$logic, :$inner);

             for %value.pairs.sort(*.key) -> $pair (:key($orig-op), :value($val)) {
                 self.debug("pair { $orig-op => $val.perl }");
                 my Clause $sub-clause = self.build-where($key => $pair, :$logic);
     
                $clauses.clauses.append: $sub-clause;
             }
             $clauses;
         }
     
         method use-special-op($key, $op, $value) {
             ?self.^lookup('where-special-op').cando(Capture.from-args(self, $key, $op, $value))
         }
     
         proto method where-special-op(|c) { * }
     
         class X::IllegalOperator is Exception {
             has Str $.op is required;
             method message() returns Str {
                 "Illegal use of top level '-{ $!op }'";
             }
         }
     
        subset FallbackOp of Str:D where { $_ !~~ m:i/(bool|and|or|ident|nest|value)/ };

        multi method where-unary-op(Str $op where /^'-'/, $rhs) returns Clause {
            self.debug("got op $op - trimming");
            samewith $op.substr(1), $rhs;
        }

        multi method where-unary-op(FallbackOp $op, $rhs where Stringy|Numeric) returns Clause {
            self.debug("got $op and $rhs");
            self.assert-pass-injection-guard($op);
            my $sql = sprintf "%s %s", self.sqlcase($op), self.convert('?');
            my @bind = self.apply-bindtype($*NESTED-FUNC-LHS // $op, $rhs);
            Expression.new(:$sql, :@bind);
        }

        multi method where-unary-op(FallbackOp $op, $rhs) returns Clause {
            self.debug("with $op and { $rhs.perl }");
            my $clause = self.build-where($rhs);
            Expression.new(sql => (sprintf '%s %s', self.sqlcase($op), $clause.sql(:inner)), bind => $clause.bind);
        }
     
     
         # not really enhancing the reputation with regard to the line-noise thing 
        multi method where-unary-op(Str $op where /:i^ and  ( [_\s]? \d+ )? $/|/:i^ or   ( [_\s]? \d+ )? $/,  @value) returns Clause {
            self.debug("array with $op");
            self.build-where(@value, logic => $op, :inner);
        }
     
        multi method where-unary-op(Str:D $op where /:i^ or   ( [_\s]? \d+ )? $/, %value) returns Clause {
            self.debug("hash with $op");
            my @value = %value.pairs.sort(*.key);
            self.build-where(@value, logic => $op, :inner);
        }
     
         multi method where-unary-op(Str:D $op where /:i^ and  ( [_\s]? \d+ )? $/, %value) returns Clause {
            self.debug("hash with $op");
             self.build-where(%value, :inner);
         }
     
         multi method where-unary-op(Str $op where /:i^ nest ( [_\s]? \d+ )? $/, Str:D $value) returns Clause {
             Expression.new(sql => $value);
         }
         
         multi method where-unary-op(Str $op where /:i^ nest ( [_\s]? \d+ )? $/, $value) returns Clause {
             self.build-where($value);
         }
     
         multi method where-unary-op(Str:D $op where /:i^  bool   $/, Str:D $value) returns Clause {
             self.debug("bool with Str $value");
             Expression.new(sql => self.convert(self.quote($value)));
         }
     
         multi method where-unary-op(Str:D $op where /:i^ bool     $/, $value) returns Clause {
             self.debug("bool with other $value");
             self.build-where($value);
         }
     
         multi method where-unary-op(Str:D $op where m:i/^ ( not \s ) bool     $/, $value) returns Clause {
             my $clause = samewith 'bool', $value;
             Expression.new(sql => "NOT " ~ $clause.sql(:inner), bind => $clause.bind);
         }
     
        # Equality expression
         multi method where-unary-op(Str $op where m:i/^ ident                  $/, Cool $lhs, Cool $rhs) returns Clause {
             Expression.new( sql => self.convert(self.quote($lhs)) ~ " = " ~ self.convert(self.quote($rhs)));
         }
     
         
        # Null Expression
         multi method where-unary-op(Str $op where m:i/^ value                  $/, Cool $lhs, Cool:U $rhs?) returns Clause {
             defined $lhs ?? Expression.new(sql => self.convert(self.quote($lhs)) ~ ' IS NULL') !! Expression;
         }
     
        # Equality Expression with bind;
         multi method where-unary-op(Str $op where m:i/^ value                  $/, Cool $lhs, Cool:D $rhs) returns Clause {
             my @bind = self.apply-bindtype( $lhs.defined ?? $lhs !! $*NESTED-FUNC-LHS // Any, $rhs).flat;
             my $sql = $lhs ?? self.convert(self.quote($lhs)) ~ ' = ' ~ self.convert('?') !! self.convert('?');
             Expression.new(:$sql, :@bind);
         }
     
     
     
     
         multi method where-special-op(Str $key, Str $op where /:i^ is ( \s+ not )?     $/, Any:U $) returns Clause {
             Expression.new(sql => (self.convert(self.quote($key)), ($op, 'null').map(-> $v { self.sqlcase($v) })).join(' '));
     
         }
     
         proto method where-field-op(|c) { * }
     
         multi method where-field-op(Str $key, Str $op, @vals where *.elems > 0, Bool :$inner) returns Clause {
             my @values  = @vals;
             my $logic = 'or';
             if @values[0].defined && @values[0] ~~ m:i/^ \- $<logic>=( AND|OR ) $/ {
                 $logic = $/<logic>.Str.uc;
                 @values.shift;
             }
             ExpressionGroup.new(clauses =>self.build-where(@values.map( -> $v { $key => $op =>  $v }), $logic), :$logic, :$inner);
         }
     
         multi method where-field-op(Str $key, Str:D $op where $!equality-op, @values where *.elems == 0, Bool :$inner) returns Clause {
             Expression.new(sql => $!sqlfalse);
         }
     
         multi method where-field-op(Str $key, Str:D $op where $!inequality-op, @values where *.elems == 0, Bool :$inner) {
             Expression.new(sql => $!sqltrue);
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

         multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? between $/, @values where *.elems == 2 ) returns Clause {
             self.debug("between with { @values.perl }");
             my $label           = self.convert($key, :quote);
             my $and             = self.sqlcase('and');
             my $placeholder     = self.convert('?');
             $op                 = self.sqlcase($op);
     
             
             my @clauses;
             for @values -> $value {
                 my $sub-clause = do given $value {
                     when Cool {
                         Expression.new(sql => $placeholder, bind => self.apply-bindtype($key, $value).flat);
                     }
                     when Pair {
                         my $func = $value.key.subst(/^\-/,'');
                         self.where-unary-op($func => $value.value);
                     }
                 }
                 @clauses.append: $sub-clause;
             }
     
             Between.new(lhs => @clauses[0], rhs => @clauses[1], :$label, :$op, :$and);
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
     
         multi method where-special-op(Str $key, Str $op where /:i^ ( not \s )? in      $/, *@values) returns Clause {
             samewith $key, $op, @values;
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

         multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, @values where { $_ !~~ SqlLiteral && $_.elems > 0 }) returns Clause {
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
                         self.where-unary-op($value).flat;
                     }
     
                 }
                 @clauses.append: $sub-clause;
             }

             In.new(:$op, :$label, :@clauses);
         }
     
         multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, @values where *.elems == 0) returns Clause {
             my $sql = $op ~~ m:i/<|w>not<|w>/ ?? $!sqltrue !! $!sqlfalse;
             Expression.new(:$sql);
         }
     
         multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, SqlLiteral $values ) returns Clause {
             my $label       = self.convert($key, :quote);
             $op             = self.sqlcase($op);
             my ( $sql, @bind) = $values.list;
             self.assert-bindval-matches-bindtype(@bind);
             $sql = self.open-outer-paren($sql);
             Expression.new(sql => "$label $op ( $sql )", :@bind);
         }
    }

    # Transitional
    method where(|c) {
        my $w = Where.new(|c);
        ($w.sql, $w.bind);
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

    class OrderBy does Statement {
    }

    class Join does Statement {
    }

    class Select does Statement {
        has $.from;
        has @.fields;
        has Where $.where;
        has OrderBy $.order-by;
        has Join @.join;

    }

    proto method select(|c) { * }

    multi method select($table, @fields,  :$where, :$order, :$join) returns Select {
        my $f = @fields.map(-> $v { self.quote($v) }).join(', ');
        samewith $table, $f, :$where, :$order, :$join;
    }


    multi method select($table, *@fields, :$where, :$order, :$join) returns Select {
        my $table-name = self.table($table);
        my Where $where-clause = self.where($where).flat;
        my $sql = join(' ', self.sqlcase('select'), @fields, self.sqlcase('from'),   $table-name) ~ $where-clause.sql;
        Select.new(from => $table-name, :@fields, where => $where-clause);
    }

    method delete($table, :$where) {
        my $table-name = self.table($table);

        my ($where-sql, @bind) = self.where($where).flat;
        my $sql = self.sqlcase('delete from') ~ " $table-name" ~ $where-sql;

        ($sql, @bind);
    }

    method order-by($arg) {
        my (@sql, @bind);
        for self.order-by-chunks($arg) -> $c {
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
        my $sql = @sql ?? sprintf '%s %s', self.sqlcase(' order by'), @sql.join(', ') !! '';
        ($sql, @bind)
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
        has Str $.message = 'key passed to order-by must be "-desc" or "-asc"';
    }

    multi method order-by-chunks(Pair $arg) {
        my @ret;
        if $arg.key ~~ /^\-$<direction>=(desc|asc)/ {
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


    proto method table(|c) { * }

    multi method table(@tables) returns Str {
        @tables.map(-> $name { self.quote($name) }).join(', ');
    }

    multi method table(Str $table) returns Str {
        self.quote($table);
    }




}

# vim: expandtab shiftwidth=4 ft=perl6
