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

    has $.array-datatypes;

    has Str $.case where 'lower'|'upper' = 'upper';
    has Str $.logic where 'OR'|'AND' = 'OR';
    has Str $.bindtype = 'normal';
    has Str $.cmp = '=';

    has Regex $!equality-op   = do { my $cmp = $!cmp; rx:i/^( $cmp | \= )$/ };
    has Regex $!inequality-op = rx:i/^( '!=' | '<>' )$/;
    has Regex $!like-op       = rx:i/^ (is\s+)? r?like $/;
    has Regex $!not-like-op   = rx:i/^ (is\s+)? not \s+ r?like $/;

    has $.convert;

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

    has Bool $.debug = False;

    method debug(*@args) {
        if $!debug {
            note "[{ callframe(2).code.?name }] ", @args;
        }
    }

    role LiteralValue { }

    role SqlLiteral does LiteralValue {
    }

    multi sub SQL($literal, *@bind) returns LiteralValue is export {
        [$literal, @bind] but SqlLiteral
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



    class X::Injection is Exception {
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


    role Select does LiteralValue {
    }

    proto method select(|c) { * }

    multi method select($table, @fields,  :$where, :$order) {
        my $f = @fields.map(-> $v { self.quote($v) }).join(', ');
        samewith $table, $f, :$where, :$order;
    }


    multi method select($table, $fields = '*', :$where, :$order) {
        my $table-name = self.table($table);
        my ($where-sql, @bind) = self.where($where, $order).flat;
        self.debug("Got bind values { @bind.perl }");
        my $sql = join(' ', self.sqlcase('select'), $fields, self.sqlcase('from'),   $table-name) ~ $where-sql;
        ($sql, @bind) but Select;
    }

    method delete($table, :$where) {
        my $table-name = self.table($table);

        my ($where-sql, @bind) = self.where($where).flat;
        my $sql = self.sqlcase('delete from') ~ " $table-name" ~ $where-sql;

        ($sql, @bind);
    }

    role Where does LiteralValue {
    }

    proto method where(|c) { * }

    multi method where(Any:U $, Any:U $) {
        self.debug("no where");
        ('', []) but Where;
    }

    multi method where(Any:D $where, Any:U $) {
        samewith $where;
    }

    multi method where(*%where) {
        self.debug("slurpy");
        samewith %where;
    }

    multi method where(Any:D $where) {
        my ($sql, $bind) = self.build-where($where);
        $bind = $bind.Array;
        self.debug("(no order) got bind values { $bind.perl } ");
        $sql = $sql ?? self.sqlcase(' where ') ~ "( $sql )" !! '';
        ($sql, $bind) but Where;
    }



    multi method where($where, Any:D $order ) {
        self.debug("Got order $order");
        my ($sql, $bind) = samewith $where;
        self.debug("(order) got bind values { $bind.perl } { $bind.VAR.perl } ");
        my ($order-sql, @order-bind) = self.order-by($order).flat;
        $sql ~= $order-sql;
        $bind.append: @order-bind;
        ($sql, $bind) but Where;
    }


    proto method build-where(|c) { * }

    subset Logic of Str where { $_.defined && $_.uc ~~ "OR"|"AND" };

    multi method build-where(@where, Any:U $logic?) {
        (samewith @where, :$!logic).flat;
    }

    multi method build-where(@where, Logic $logic) {
        (samewith @where, :$logic).flat;
    }

    multi method build-where(@where, Logic :$logic = $!logic) {
        my @clauses = @where;
        self.debug("(Array) got clauses { @where.perl }");

        my (@sql-clauses, @all-bind);
        while @clauses.elems {
            my $el = @clauses.shift;

            my ($sql, @bind) = do given $el {
                when Positional {
                    self.debug("positional clause");
                    self.build-where($el, :$logic).flat;
                }
                when Associative|Pair {
                    self.debug("pair clause");
                    self.build-where($el, logic => 'and').flat;
                }
                when Str {
                    self.debug("Str clause");
                    self.build-where($el => @clauses.shift, :$logic).flat;
                }
                default {
                    self.debug("fallback with { $el.perl } and logic ($logic)");
                    self.build-where($el, :$logic).flat;
                }
            }
            if $sql {
                self.debug("Got inner bind { @bind.perl }");
                @sql-clauses.append: $sql;
                @all-bind.append: @bind.map({ $_.flat }).flat;
            }
        }

        self.debug("about to join clauses with bind { @all-bind.perl }");
        self.join-sql-clauses($logic, @sql-clauses, @all-bind); #.flat;
    }


    multi method build-where(Str :$logic, *%where) {
        self.debug("slurpy");
        samewith %where, :$logic;
    }

    multi method build-where($where, Str :$logic) {
        [$where, () ];
    }

    multi method build-where(%where where * !~~ Pair, Str :$logic) {
        my (@sql-clauses, @all-bind);

        self.debug("hash -> { %where.perl } ");

        for %where.pairs.sort(*.key) -> Pair $pair {
            self.debug("got pair { $pair.perl } ");
            my ( $sql, $bind ) = self.build-where($pair, :$logic);
            self.debug("Got bind { $bind.^name } { $bind.cache.perl }");
            @sql-clauses.append: $sql;
            @all-bind.append: $bind.cache.grep(*.defined).map(*.flat).flat if $bind;
        }
        self.debug("(hash) about to join clauses with bind { @all-bind.perl }");
        self.join-sql-clauses('and', @sql-clauses, @all-bind);
    }

    role LiteralPair does SqlLiteral {
    }

    multi method build-where(Pair $p where * !~~ LiteralPair ( Str :$key where * ~~ /^\-./, Str :$value), Str :$logic) {
        my $op = $key.substr(1).trim.subst(/^not_/, 'NOT ', :i);
        self.debug("Pair not Literal but Key is $key (String value $value)");
        my ( $s, $bind) = self.where-unary-op($op, $value);
        ($s, $bind);
    }

    multi method build-where(Pair $p where * !~~ LiteralPair ( Str :$key where * ~~ /^\-./, :$value), Str :$logic) {
        my $op = $key.substr(1).trim.subst(/^not_/, 'NOT ', :i);
        self.debug("Pair not Literal but Key is $key (op is $op)");
        my ( $s, $b) = self.where-unary-op($op, $value);
        ($s, $b.flat);
    }

    multi method build-where(Pair $p ( Str :$key, :$value where Stringy|Numeric ), Str :$logic) {
        self.debug("Pair with Stringy|Numeric value");
        flat ( "$key { self.sqlcase($!cmp) } ?", self.apply-bindtype($key, $value));
    }


    multi method build-where(Pair $p where * !~~ LiteralPair ( Str:D :$key where { $_  ~~ m:i/^\-[AND|OR]$/ }, :@value where *.elems > 0 ), Str :$logic) {
        my $new-logic = $key.substr(1).lc;
        self.debug("got a pair with an/or op will redispatch with logic $new-logic");
        (samewith @value, logic => $new-logic).flat;
    }


    multi method build-where(Pair $p where * !~~ LiteralPair ( :$key, :@value where { $_ !~~ SqlLiteral && $_.elems > 0 }), Str :$logic is copy) {
        my @values = @value;
        self.debug("pair $key => { @values.perl } logic({ $logic // '<undefined>'})");
        self.debug($p.WHAT);
        my $op = @values[0].defined && @values[0].can('match') && @values[0] ~~ m:i/^\-[AND|OR]$/ ?? @values.shift !! '';
        my @distributed = @values.map(-> $v { $v ~~ Callable ?? $v().hash !! $v }).map(-> $v { $key => $v });

        if $op {
            self.debug('adding op');
            @distributed.prepend: $op;
        }

        $logic = $op ?? $op.substr(1) !! $logic;
        self.debug("redistributing array with '{ $logic // "<undefined>" }' with a { @distributed.perl }");
        self.build-where(@distributed, :$logic).flat;
    }

    multi method build-where(Pair $p ( :$key, :@value where *.elems == 0), Str :$logic) {
        ($!sqlfalse, ());
    }

    multi method build-where(Pair $p ( :$key, Any:U :$value), Str :$logic) {
        (self.quote($key) ~ self.sqlcase(" is null"), ());
    }


    multi method build-where(Pair $p ( :$key, SqlLiteral :$value ), Str :$logic ) {
        self.debug("got pair  with SqlLiteral value { $p.perl }");
        (samewith $p but LiteralPair, :$logic).flat;
    }

    multi method build-where(LiteralPair $p (:$key, :@value where *.elems > 1), Str :$logic) {
        self.debug("Literal pair { $p.perl }");
        my ($sql, $bind) = @value;
        self.debug("Got bind from literal { $bind.perl }");
        my $s = self.quote($key) ~ " $sql";
        ($s, $bind);
    }

    multi method build-where(LiteralPair $p (:$key, :@value where *.elems == 1), Str :$logic) {
        self.debug("Literal pair (no bind) { $p.perl }");
        my ($sql) = @value;
        my $s = self.quote($key) ~ " $sql";
        ($s, []);
    }


    multi method build-where(@value where { $_ ~~ SqlLiteral && $_.elems > 1 }, Str :$logic) {
        self.debug("SqlLiteral with more bind");
        my ($sql, $bind) = @value;
        ($sql, $bind.flat);
    }

    multi method build-where(@value where { $_ ~~ SqlLiteral && $_.elems == 1 }, Str :$logic) {
        self.debug("SqlLiteral with no bind");
        my ($sql) = @value;
        ($sql);
    }


    multi method build-where(Pair $p ( :$key, :%value), Str :$logic = 'and') {
        self.debug("Got a pair with a hash value");
        my $*NESTED-FUNC-LHS = $*NESTED-FUNC-LHS // $key;
        my ($all-sql, @all-bind);

        for %value.pairs.sort(*.key) -> $ (:key($orig-op), :value($val)) {
            self.debug("pair { $orig-op => $val.perl }");
            my ($sql, $bind);
            my $op = $orig-op.subst(/^\-/,'').trim.subst(/\s+/, ' ');
            self.assert-pass-injection-guard($op);
            $op ~~ s:i/^is_not/IS NOT/;
            $op ~~ s:i/^not_/NOT /;

            if $orig-op ~~ m:i/^\-$<logic>=(and|or)/ {
                ($sql, $bind) = self.build-where($key => $val, logic => ~$/<logic>).flat;
            }
            elsif self.use-special-op($key, $op, $val) {
                self.debug("use-special-up said yes to $key $op $val");
                ($sql, $bind) = self.where-special-op($key, $op, $val);
                $bind = $bind.list;
                self.debug("special op returned bind { $bind.perl }");
            }
            else {
                given $val {
                    when Positional {
                        ($sql, $bind) = self.where-field-op($key, $op, $val);
                    }
                    when Any:U {
                        self.debug("NULL with $op");
                        my $is = do given $op {
                            when $!equality-op|$!like-op {
                                'is'
                            }
                            when $!inequality-op|$!not-like-op {
                                'is not'
                            }
                            default {
                                die "unexpectated operator '$op' for NULL";
                            }
                        }
                        $sql = self.quote($key) ~ self.sqlcase(" $is null");
                    }
                    default {
                        self.debug("default");
                        ($sql, $bind) = self.where-unary-op($op, $val).flat;
                        $sql = join(' ', self.convert(self.quote($key)), $*NESTED-FUNC-LHS && $*NESTED-FUNC-LHS eq $key ?? $sql !! "($sql)");
                    }
                }
            }

            ($all-sql) = ($all-sql.defined and $all-sql) ?? self.join-sql-clauses($logic // 'and', [$all-sql, $sql], []) !! $sql;
            self.debug("Adding bind { $bind.perl }");
            @all-bind.append: $bind.list if $bind.defined;
        }
        self.debug("returning bind { @all-bind.perl }");
        ($all-sql, @all-bind.item);
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

    multi method where-unary-op(Str $op, $rhs) {

        self.debug("Generic unary OP: $op - recursing as function");

        self.assert-pass-injection-guard($op);

        my ($sql, @bind) = do given $rhs {
            when Stringy|Numeric {
                if $*NESTED-FUNC-LHS {
                    (self.convert('?'), self.apply-bindtype($*NESTED-FUNC-LHS, $rhs)).flat;
                }
                else {
                    (self.convert('?'), self.apply-bindtype($op, $rhs)).flat;
                }
            }
            default {
                self.debug("default with $rhs"); 
                self.build-where($rhs).flat;
            }
        }


        $sql = sprintf '%s %s', self.sqlcase($op), $sql;
        self.debug("got unary-op sql -> $sql and bind { @bind.perl }");
        return ($sql, @bind);
    }


    # not really enhancing the reputation with regard to the line-noise thing 
    multi method where-unary-op(Str $op where /:i^ and  ( [_\s]? \d+ )? $/|/:i^ or   ( [_\s]? \d+ )? $/,  @value) {
        self.build-where(@value, logic => $op).flat;
    }

    multi method where-unary-op(Str:D $op where /:i^ or   ( [_\s]? \d+ )? $/, %value) {
        my @value = %value.pairs.sort(*.key);
        self.build-where(@value, logic => $op).flat;
    }

    multi method where-unary-op(Str:D $op where /:i^ and  ( [_\s]? \d+ )? $/, %value) {
        self.build-where(%value).flat;
    }

    multi method where-unary-op(Str $op where /:i^ nest ( [_\s]? \d+ )? $/, Str:D $value) {
        ($value);
    }
    
    multi method where-unary-op(Str $op where /:i^ nest ( [_\s]? \d+ )? $/, $value) {
        self.build-where($value).flat;

    }


    multi method where-unary-op(Str:D $op where /:i^  bool   $/, Str:D $value) {
        self.debug("bool with Str $value");
        self.convert(self.quote($value)).flat;
    }

    multi method where-unary-op(Str:D $op where /:i^ bool     $/, $value) {
        self.debug("bool with other $value");
        self.build-where($value);
    }

    multi method where-unary-op(Str:D $op where m:i/^ ( not \s ) bool     $/, $value) {
        my ($s, @b) = (samewith 'bool', $value).flat;
        $s = "NOT $s";
        ($s, @b);
    }

    multi method where-unary-op(Str $op where m:i/^ ident                  $/, Cool $lhs, Cool $rhs) {
        self.convert(self.quote($lhs)) ~ " = " ~ self.convert(self.quote($rhs));
    }

    
    multi method where-unary-op(Str $op where m:i/^ value                  $/, Cool $lhs, Cool:U $rhs?) {
        defined $lhs ?? self.convert(self.quote($lhs)) ~ ' IS NULL' !! Any;
    }

    multi method where-unary-op(Str $op where m:i/^ value                  $/, Cool $lhs, Cool:D $rhs) {
        my @bind = self.apply-bindtype( $lhs.defined ?? $lhs !! $*NESTED-FUNC-LHS // Any, $rhs).flat;
        $lhs ?? (self.convert(self.quote($lhs)) ~ ' = ' ~ self.convert('?'), @bind) !! (self.convert('?'), @bind);
    }




    multi method where-special-op(Str $key, Str $op where /:i^ is ( \s+ not )?     $/, Any:U $) {
        (self.convert(self.quote($key)), ($op, 'null').map(-> $v { self.sqlcase($v) })).join(' ');

    }

    proto method where-field-op(|c) { * }

    multi method where-field-op(Str $key, Str $op, @vals where *.elems > 0) {
        my @values  = @vals;
        my $logic;
        if @values[0].defined && @values[0] ~~ m:i/^ \- $<logic>=( AND|OR ) $/ {
            $logic = $/<logic>.Str.uc;
            @values.shift;
        }
        self.build-where(@values.map( -> $v { $key => $op =>  $v }), $logic);
    }

    multi method where-field-op(Str $key, Str:D $op where $!equality-op, @values where *.elems == 0) {
        $!sqlfalse;
    }

    multi method where-field-op(Str $key, Str:D $op where $!inequality-op, @values where *.elems == 0) {
        $!sqltrue;
    }



    # BETWEEN
    multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? between $/, @values where *.elems == 2 ) {
        self.debug("between with { @values.perl }");
        my $label           = self.convert($key, :quote);
        my $and             = ' ' ~ self.sqlcase('and') ~ ' ';
        my $placeholder     = self.convert('?');
        $op                 = self.sqlcase($op);

        
        my ( @all-sql, @all-bind);
        for @values -> $value {
            my ( $s, @b) = do given $value {
                when Cool {
                    ($placeholder, self.apply-bindtype($key, $value)).flat;
                }
                when Pair {
                    my $func = $value.key.subst(/^\-/,'');
                    self.where-unary-op($func => $value.value).flat;
                }
            }
            @all-sql.append: $s;
            @all-bind.append: @b;
        }

        self.debug("between returning bind { @all-bind.perl }");

        my $sql = "( $label $op " ~ @all-sql.join($and) ~ " )";
        ($sql, @all-bind.flat);
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

    multi method where-special-op(Str $key, Str $op where /:i^ ( not \s )? in      $/, *@values) {
        (samewith $key, $op, @values).flat;
    }

    multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, @values where { $_ !~~ SqlLiteral && $_.elems > 0 }) {
        self.debug("Literal") if @values ~~ SqlLiteral;
        self.debug("KEY: $key OP : $op  VALUES { @values.perl }");
        my $label       = self.convert($key, :quote);
        my $placeholder = self.convert('?');
        $op             = self.sqlcase($op);

        my (@all-sql, @all-bind);

        for @values -> $value {
            my ( $sql, @bind) = do given $value {
                when SqlLiteral {
                    my ($sql, @bind) = $value.list;
                    self.assert-bindval-matches-bindtype(@bind);
                    ($sql, @bind);
                }
                when Stringy|Numeric {
                    ($placeholder, $value);
                }
                when Pair {
                    self.debug("pair { $value.perl }");
                    self.where-unary-op($value).flat;
                }

            }
            @all-sql.append: $sql;
            @all-bind.append: @bind;
        }
        self.debug("IN with bind { @all-bind.perl }");
        ( sprintf('%s %s ( %s )', $label, $op, @all-sql.join(', ')), self.apply-bindtype($key, @all-bind)).flat;
    }

    multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, @values where *.elems == 0) {
        my $sql = $op ~~ m:i/<|w>not<|w>/ ?? $!sqltrue !! $!sqlfalse;
        return ($sql);
    }

    multi method where-special-op(Str $key, Str $op is copy where /:i^ ( not \s )? in      $/, SqlLiteral $values ) {
        my $label       = self.convert($key, :quote);
        $op             = self.sqlcase($op);
        my ( $sql, @bind) = $values.list;
        self.assert-bindval-matches-bindtype(@bind);
        $sql = self.open-outer-paren($sql);
        ("$label $op ( $sql )", @bind);
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

    class X::InvalidBind is Exception {
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

    method sqlcase(Str $sql) returns Str {
        $!case eq 'lower' ?? $sql.lc !! $sql.uc;
    }

}

# vim: expandtab shiftwidth=4 ft=perl6
