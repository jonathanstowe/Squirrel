use v6.c;

class Squirrel {

    has $.array-datatypes;

    # TODO: clearly this hack is better served by a multi with a regex where
    has @.special-ops = (
        {regex => rx:i/^ ( not \s )? between $/, handler => 'where-field-BETWEEN'},
        {regex => rx:i/^ ( not \s )? in      $/, handler => 'where-field-IN'},
        {regex => rx:i/^ ident                 $/, handler => 'where-op-IDENT'},
        {regex => rx:i/^ value                 $/, handler => 'where-op-VALUE'},
        {regex => rx:i/^ is ( \s+ not )?     $/, handler => 'where-field-IS'},
    );

    has @.unary-ops = (
        { regex => rx:i/^ and  ( [_\s]? \d+ )? $/, handler => 'where-op-ANDOR' },
        { regex => rx:i/^ or   ( [_\s]? \d+ )? $/, handler => 'where-op-ANDOR' },
        { regex => rx:i/^ nest ( [_\s]? \d+ )? $/, handler => 'where-op-NEST' },
        { regex => rx:i/^ ( not \s )? bool     $/, handler => 'where-op-BOOL' },
        { regex => rx:i/^ ident                  $/, handler => 'where-op-IDENT' },
        { regex => rx:i/^ value                  $/, handler => 'where-op-VALUE' },
    );

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

    has $.quote-char = ',';

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

#======================================================================
# DEBUGGING AND ERROR REPORTING
#======================================================================

    has Bool $.debug = False;

    method debug(*@args) {
        if $!debug {
            note "[{ callframe(2).code.?name }] ", @args;
        }
    }

    role LiteralValue { }

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


#======================================================================
# INSERT methods
#======================================================================

    method insert($table, $data, *%options) {
        my $table-name   = self.table($table);

        my ($sql, @bind) = self.build-insert($data);

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

        my @fields = %data.keys.sort;

        my ($sql, @bind) = self.insert-values(%data);

        for @fields <-> $field {
            $field = self.quote($field);
        }

        $sql = '( ' ~ @fields.join(', ') ~ ') ' ~ $sql;

        flat ($sql, @bind);
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

        for @data -> $value {
            my ($values, @bind) = self.insert-value(Str, $value);
            @values.append: $values;
            @all-bind.append: @bind;
        }

        my $sql = self.sqlcase('values') ~ ' ( ' ~ @values.join(", ") ~ ' )';
        self.debug("returning ($sql, { @all-bind.perl }");
        flat ($sql, @all-bind);
    }

=begin later

# 
sub _insert_ARRAYREFREF { # literal SQL with bind
  my ($self, $data) = @_;

  my ($sql, @bind) = @$($data);
  $self._assert_bindval_matches_bindtype(@bind);

  return ($sql, @bind);
}
=end later


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
        my $sql = self.sqlcase('values') ~ ' ( ' ~ @values.join(", ") ~ ' )';
        flat ($sql, @all-bind);
    }

    proto method insert-value(|c) { * }

    multi method insert-value(Pair $p) {
        samewith $p.key, $p.value;
    }

    multi method insert-value(Str $column, @value) {
        my (@values, @all-bind);
        if $!array-datatypes {
            @values.append: '?';
            @all-bind.append: self.apply-bindtype($column, @value);
        }
        else {
            my ( $sql, @bind) = @value;
            self.assert-bindval-matches-bindtype(@bind);
            @values.append: $sql;
            @all-bind.append: @bind;
        }
        flat (@values.join(', '), @all-bind);
    }

    multi method insert-value(Str $column, %value) {
        my (@values, @all-bind);
        @values.append: '?';
        @all-bind.append: self.apply-bindtype($column, %value);
        flat (@values.join(', '), @all-bind);
    }

    multi method insert-value(Str $column, $value) {
        flat (($value),);
    }

    method update(Str $table, %data, :$where, *%options) {
        my $table-name = self.table($table);

        my ( @set, @all-bind);

        for %data.pairs.sort(*.key) -> $p {
            my ( @s, @b) = self.build-update($p);
            @set.append: @s;
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
        samewith $p.key, $p.value.list;
    }

    multi method build-update(Str $key, @values) {
        my ( @set, @all-bind);
        my $label = self.quote($key);
        if $!array-datatypes {
            @set.append: "$label = ?";
            @all-bind.append: self.apply-bindtype($key, @values);
        }
        else { 
            my ($sql, @bind) = @values;
            self.assert-bindval-matches-bindtype(@bind);
            @set.append: "$label = $sql";
            @all-bind.append: @bind;
        }
        flat (@set, @all-bind);
    }

    class X::InvalidOperator is Exception {
        has $.message = "Not a valid operator";
    }

    multi method build-update(Str $key, Pair $p) {
        my $*NESTED-FUNC-LHS = $key;
        my ( @set, @all-bind);
        if $p.key ~~ /^\-$<op>=(.+)/ { 
            my ($sql, @bind) = self.where-unary-op(~$/<op>, $p.value);
            say ~$/<op> 
        }
        else {
            X::InvalidOperator.new.throw;
        }
        flat ( @set, @all-bind);
    }


    proto method select(|c) { * }

    multi method select(Str $table, @fields,  :$where, :$order) {
        my $f = @fields.map(-> $v { self.quote($v) }).join(', ');
        samewith $table, $f, :$where, :$order;
    }

    multi method select(Str $table, $fields = '*', :$where, :$order) {
        my ($where-sql, @bind) = self.where($where, $order).flat;
        self.debug("Got bind values { @bind.perl }");
        my $sql = join(' ', self.sqlcase('select'), $fields, self.sqlcase('from'),   $table) ~ $where-sql;
        ($sql, @bind);
    }

#======================================================================
# DELETE
#======================================================================


    method delete(Str $table, :$where) {
        my $table-name = self.table($table);

        my ($where-sql, @bind) = self.where($where);
        my $sql = self.sqlcase('delete from') ~ " $table-name " ~ $where-sql;

        ($sql, @bind);
    }


#======================================================================
# WHERE: entry point
#======================================================================



# Finally, a separate routine just to handle WHERE clauses
    proto method where(|c) { * }

    multi method where($where) {
        my ($sql, @bind) = self.build-where($where).flat;
        $sql = $sql ?? self.sqlcase(' where ') ~ "( $sql )" !! '';
        ($sql, @bind);
    }

    multi method where($where, $order ) {
        my ($sql, @bind) = (samewith $where).flat;
        self.debug("got bind values { @bind.perl } ");
        my ($order-sql, @order-bind) = self.order-by($order).flat;
        $sql ~= $order-sql;
        @bind.append: @order-bind;
        ($sql, @bind);
    }


    proto method build-where(|c) { * }

    subset Logic of Str where { $_.uc ~~ "OR"|"AND" };

    multi method build-where(@where, Logic :$logic = $!logic) {

        my @clauses = @where;

        my (@sql-clauses, @all-bind);
        while @clauses.elems {
            my $el = @clauses.shift;

            my ($sql, @bind) = do given $el {
                when Positional {
                    self.build-where($el);
                }
                when Associative|Pair {
                    self.build-where($el, 'and');
                }
                when Str {
                    self.build-when($el => @clauses.shift);
                }
            }
            if $sql {
                @sql-clauses.append: $sql;
                @all-bind.append: @bind;
            }
        }
        self.join-sql-clauses($logic, @sql-clauses, @all-bind);
    }

    multi method build-where(:$logic, *%where) {
        self.debug("slurpy");
        samewith %where, :$logic;
    }
    multi method build-where(%where, :$logic) {
        my (@sql-clauses, @all-bind);

        self.debug("hash");

        for %where.pairs.sort(*.key) -> $pair {
            self.debug("got pair { $pair.perl }");
            my ( $sql, @bind ) = self.build-where($pair, :$logic);
            @sql-clauses.append: $sql;
            @all-bind.append: @bind;
        }
        self.join-sql-clauses('and', @sql-clauses, @all-bind);
    }

    multi method build-where(Pair $p ( Str :$key where * ~~ /^\-./, :$value), :$logic) {
        my $op = $key.substr(1).trim.subst(/^not_/, 'NOT ', :i);
        my ( $s, @b) = self.where-unary-op($op, $value);
        $s = "($s)" unless self.is-unary-operator($op) || self.is-nested-func-lhs($key);
        ($s, @b);
    }

    multi method build-where(Pair $p ( Str :$key, :$value ), :$logic) {
        flat ( "$key = ?", ($value,));
    }

    multi method build-where(Pair $p ( :$key, :@value is copy where *.elems > 0)) {
        my $op = @value[0].defined && @value[0] ~~ m:i/^\-[AND|OR]$/ ?? @value.shift !! '';
        my @distributed = @value.map(-> $v { $key => $v });

        if $op {
            @distributed.prepend: $op;
        }
        my $logic = $op ?? $op.substr(1) !! '';

        self.build-where(@distributed, $logic);
    }

    multi method build-where(Pair $p ( :$key, :@value where *.elems == 0)) {
        ($!sqlfalse, ());
    }


    multi method build-where(Pair $p ( :$key, :%value), Str $logic = 'and') {
        my $*NESTED-FUNC-LHS = $*NESTED-FUNC-LHS // $key;
        my ($all-sql, @all-bind);

        for %value.pairs.sort(*.key) -> $ (:key($orig-op), :value($val)) {
            my ($sql, @bind);
            my $op = $orig-op.subst(/^\-/,'').trim.subst(/\s+/, ' ');
            self.assert-pass-inject-guard($op);
            $op ~~ s:i/^is_not/IS NOT/;
            $op ~~ s:i/^not_/NOT /;

            if $orig-op ~~ m:i/^\-$<logic>=(and|or)/ {
                ($sql, @bind) = self.build-where($key => $val, ~$/<logic>);
            }
            elsif @!special-ops.grep( -> $so { $op ~~ $so<regex> }).first -> $special-op {
                ($sql, @bind) = do given $special-op<handler> {
                    when Code {
                        self.$_($key, $op, $val);
                    }
                    when Str {
                        self."$_"($key, $op, $val);
                    }
                    default {
                        die "WTF! $_ in special-op";
                    }
                }

            }
            else {
                given $val {
                    when Positional {
                        ($sql, @bind) = self.where-field-op($key, $op, $val);
                    }
                    when Any:U {
                        my $is = do given $op {
                            when $!equality-op {
                                'is'
                            }
                            when $!inequality-op {
                                'is not'
                            }
                        }
                        $sql = self.quote($key) ~ self.sqlcase(" $is null");
                    }
                    default {
                        ($sql, @bind) = self.where-unary-op($op, $val);
                        $sql = join(' ', self.convert(self.quote($key)), $*NESTED-FUNC-LHS && $*NESTED-FUNC-LHS eq $key ?? $sql !! "($sql)");
                    }
                }
            }

            ($all-sql) = ($all-sql.defined and $all-sql) ?? self.join-sql-clauses($logic, [$all-sql, $sql], []) !! $sql;
            @all-bind.append: @bind;
        }
        ($all-sql, @all-bind);
    }

    method is-unary-operator(Str $op) returns Bool {
        so @!unary-ops.grep(-> $uo { $op ~~ $uo<regex> });
    }

    method is-nested-func-lhs(Str $key) returns Bool {
        $*NESTED-FUNC-LHS && $*NESTED-FUNC-LHS eq $key;
    }

    
    class X::IllegalOperator is Exception {
        has Str $.op is required;
        method message() returns Str {
            "Illegal use of top level '-{ $!op }'";
        }
    }

    method where-unary-op(Str $op, $rhs) {

        if !$*NESTED-FUNCTION-LHS and @!special-ops.grep(-> $so { $op ~~ $so<regex> }) {
            X::IllegalOperator.new(:$op).throw;
        }

        if @!unary-ops.grep(-> $uo { $op ~~ $uo<regex> }).first -> $op-entry {
            my $handler = $op-entry<handler>;
            given $handler {
                when Str {
                    return self."$handler"($op,$rhs);
                }
                when Code {
                    return self.$handler($op,$rhs);
                }
                default {
                    die "not a valid op handler";
                }

            }
        }

        self.debug("Generic unary OP: $op - recursing as function");

        self.assert-pass-injection-guard($op);

        my ($sql, @bind) = do given $rhs {
            when Str {
                if $*NESTED-FUNC-LHS {

                }
                else {
                    (self.convert('?'), self.apply-bindtype($*NESTED-FUNC-LHS, $rhs));
                }
            }
            default {
                self.build-where($rhs);
            }
        }

        $sql = sprintf '%s %s', self.sqlcase($op), $sql;
        return ($sql, @bind);
    }

    proto method where-op-ANDOR(|c) { * }

    multi method where-op-ANDOR(Str $op,  @value) {
        self.build-where(@value, $op);
    }

    multi method where-op-ANDOR(Str $op where m:i/^or/, %value) {
        my @value = %value.pairs.sort(*.key);
        self.build-where(@value, $op);
    }

    multi method where-op-ANDOR(Str $op where  * !~~ m:i/^or/, %value) {
        self.build-where(%value);
    }

    proto method where-op-NEST(|c) { * }
    
    multi method where-op-NEST(Str $op, Str:D $value) {
        ($value);
    }
    
    multi method where-op-NEST(Str $op, $value) {
        self.build-where($value);

    }

    proto method where-op-BOOL(|c) { * }

    multi method where-op-BOOL(Str $op, Str:D $value) {
        self.convert(self.quote($value));
    }

    multi method where-op-BOOL(Str $op, $value) {
        self.build-where($value);
    }

    multi method where-op-BOOL(Str:D $op where m:i/^not/, $value) {
        my ($s, @b) = samewith Str, $value;
        $s = "(NOT $s)";
        ($s, @b);
    }

    proto method where-op-IDENT(|c) { * }

    multi method where-op-IDENT(Str $op, Cool $lhs, Cool $rhs) {
        self.convert(self.quote($lhs)) ~ " = " ~ self.convert(self.quote($rhs));
    }

    proto method where-op-VALUE(|c) { * }
    
    multi method where-op-VALUE(Str $op, Cool $lhs, Cool:U $rhs?) {
        defined $lhs ?? self.convert(self.quote($lhs)) ~ ' IS NULL' !! Any;
    }

    multi method where-op-VALUE(Str $op, Cool $lhs, Cool:D $rhs) {
        my @bind = self.apply-bindtype( $lhs.defined ?? $lhs !! $*NESTED-FUNC-LHS // Any, $rhs);
        $lhs ?? (self.convert(self.quote($lhs)) ~ ' = ' ~ self.convert('?'), @bind) !! (self.convert('?'), @bind);
    }




    proto method where-field-IS(|c) { * }

    multi method where-field-IS(Str $key, Str $op, Any:U $) {
        (self.convert(self.quote($key)), ($op, 'null').map(-> $v { self.sqlcase($v) })).join(' ');

    }

    proto method where-field-op(|c) { * }

    multi method where-field-op(Str $key, Str $op, @values is copy where *.elems > 0) {
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


=begin reference 

# I think that these are basically handled by the build-where(Pair)

sub _where_hashpair_SCALARREF {
  my ($self, $k, $v) = @_;
  self.debug("SCALAR\($k\) means literal SQL: $$v");
  my $sql = $self._quote($k) ~ " " ~ $$v;
  return ($sql);
}

# literal SQL with bind
sub _where_hashpair_ARRAYREFREF {
  my ($self, $k, $v) = @_;
  self.debug("REF\($k\) means literal SQL: @${$v}");
  my ($sql, @bind) = @$$v;
  $self._assert_bindval_matches_bindtype(@bind);
  $sql  = $self._quote($k) ~ " " ~ $sql;
  return ($sql, @bind );
}

# literal SQL without bind
sub _where_hashpair_SCALAR {
  my ($self, $k, $v) = @_;
  self.debug("NOREF\($k\) means simple key=val: $k $self.{"cmp"} $v");
  my $sql = join ' ', $self._convert($self._quote($k)),
                      $self._sqlcase($self.{'cmp'}),
                      $self._convert('?');
  my @bind =  $self._bindtype($k, $v);
  return ( $sql, @bind);
}


sub _where_hashpair_UNDEF {
  my ($self, $k, $v) = @_;
  self.debug("UNDEF\($k\) means IS NULL");
  my $sql = $self._quote($k) ~ $self._sqlcase(' is null');
  return ($sql);
}

#======================================================================
# WHERE: TOP-LEVEL OTHERS (SCALARREF, SCALAR, UNDEF)
#======================================================================


sub _where_SCALARREF {
  my ($self, $where) = @_;

  # literal sql
  self.debug("SCALAR\(*top\) means literal SQL: $$where");
  return ($$where);
}


sub _where_SCALAR {
  my ($self, $where) = @_;

  # literal sql
  self.debug("NOREF\(*top\) means literal SQL: $where");
  return ($where);
}


sub _where_UNDEF {
  my ($self) = @_;
  return ();
}

=end reference

#======================================================================
# WHERE: BUILTIN SPECIAL OPERATORS (-in, -between)
#======================================================================


    proto method where-field-BETWEEN(|c) { * }

    multi method where-field-BETWEEN(Str $key, Str $op is copy, @values where *.elems == 2 ) {
        my $label           = self.convert($key, :quote);
        my $and             = ' ' ~ self.sqlcase('and') ~ ' ';
        my $placeholder     = self.convert('?');
        $op                 = self.sqlcase($op);

        
        my ( @all-sql, @all-bind);
        for @values -> $value {
            my ( $s, @b) = do given $value {
                when Cool {
                    ($placeholder, self.apply-bindtype($key, $value));
                }
                when Pair {
                    my $func = $value.key.subst(/^\-/,'');
                    self.where-unary-op($func => $value.value);
                }
            }
            @all-sql.append: $s;
            @all-bind.append: @b;
        }

        my $sql = "( $label $op " ~ @all-sql.join($and) ~ " )";
        ($sql, @all-bind);
    }

    role ScalarLiteral does LiteralValue {
    }

    role ArrayLiteral does LiteralValue {
    }

    multi sub sql-literal(@l) {
        @l but ArrayLiteral
    }

    multi sub sql-literal($l) {
        $l but ScalarLiteral
    }

    proto method where-field-IN(|c) { * }

    multi method where-field-IN(Str $key, Str $op is copy, @values where *.elems > 0) {
        my $label       = self.convert($key, :quote);
        my $placeholder = self.convert('?');
        $op             = self.sqlcase($op);

        my (@all-sql, @all-bind);

        for @values -> $value {
            my ( $sql, @bind) = do given $value {
                when ScalarLiteral {
                    ($value, Empty);
                }
                when ArrayLiteral {
                    my ($sql, @bind) = $value.list;
                    self.assert-bindval-matches-bindtype(@bind);
                    ($sql, @bind);
                }
                when Stringy|Numeric {
                    ($placeholder, $value);
                }
                when Pair {
                    self.where-unary-op($value);
                }

            }
            @all-sql.append: $sql;
            @all-bind.append: @bind;
        }
        ( sprintf('%s %s ( %s )', $label, $op, @all-sql.join(', ')), self.apply-bindtype($key, @all-bind),);
    }

    multi method where-field-IN(Str $key, Str $op is copy, @values where *.elems == 0) {
        my $sql = $op ~~ m:i/\bnot\b/ ?? $!sqltrue !! $!sqlfalse;
        return ($sql);
    }

    multi method where-field-IN(Str $key, Str $op is copy, ScalarLiteral $values )  {
        my $label       = self.convert($key, :quote);
        $op             = self.sqlcase($op);
        my $sql = self.open-outer-paren($values);
        ("$label $op ( $sql )", Empty);
    }

    multi method where-field-in(Str $key, Str $op is copy,ArrayLiteral $values ) {
        my $label       = self.convert($key, :quote);
        $op             = self.sqlcase($op);
        my ( $sql, @bind) = $values.list;
        self.assert-bindval-matches-bindtype(@bind);
        $sql = self.open-outer-paren($sql);
        ("$label $op ( $sql )", @bind);
    }

    method open-outer-paren(Str $sql is copy) {
        while $sql ~~ /^ \s* \( $<inner>=(.*) \) \s* $/ -> $inner {
            if ~$inner<inner> ~~ /\)/ {
                # do something clever with extract_bracketed
            }
            $sql = ~$inner<inner>
        }
        $sql;
    }


#======================================================================
# ORDER BY
#======================================================================

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
            X::InvalidDirectio.new.throw;
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


#======================================================================
# UTILITY FUNCTIONS
#======================================================================

# highly optimized, as it's called way too often
    proto method quote(|c) { * }

    multi method quote(Str $label) returns Str {
        $label
    }

    multi method quote(Whatever $) {
        samewith '*';
    }

    multi method quote('*') {
        '*';
    }

=begin reference

sub _quote {
  # my ($self, $label) = @_;

  return '' unless defined @_[1];
  return $(@_[1]) if ref(@_[1]) eq 'SCALAR';

  @_[0].{'quote_char'} or
    (@_[0]._assert_pass_injection_guard(@_[1]), return @_[1]);

  my $qref = ref @_[0].{'quote_char'};
  my ($l, $r) =
      ?^$qref             ?? (@_[0].{'quote_char'}, @_[0].{'quote_char'})
    !! ($qref eq 'ARRAY') ?? @(@_[0].{'quote_char'})
    !! puke "Unsupported quote_char format: $_[0].{"quote_char"}";

  my $esc = @_[0].{'escape_char'} || $r;

  # parts containing * are naturally unquoted
  return join( @_[0].{'name_sep'}||'', map
    {+( $_ eq '*' ?? $_ !! do { (my $n = $_) ~~ s:c:P5/(\Q$esc\E|\Q$r\E)/$esc$1/; $l ~ $n ~ $r } )},
    ( @_[0].{'name_sep'} ?? split (m:P5/\Q$_[0]->{name_sep}\E/, @_[1] ) !! @_[1] )
  );
}

=end reference


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
        given $!bindtype {
            when 'columns' {
                $values.map({ [ $column, $_ ]});
            }
            default {
                $values.list;

            }
        }
    }

    class X::InvalidBind is Exception {
        has Str $.message = "bindtype 'columns' selected, you need to pass: [column_name => bind_value]";
    }
    method assert-bindval-matches-bindtype(*@bind) {
        if $!bindtype eq 'columns' {
            for @bind -> $item {
                if !$item.defined || $item !~~ Pair || $item.elems != 2 {
                    X::InvalidBind.new.throw;
                }
            }
        }
    }

    proto method join-sql-clauses(|c) { * }

    multi method join-sql-clauses(Str:D $logic, @clauses where *.elems > 1, @bind) {
        my $join = " " ~ self.sqlcase($logic) ~ " ";
        my $sql = '( ' ~ @clauses.join($join) ~ ' )';
        ($sql, @bind);
    }
    multi method join-sql-clauses(Str:D $logic, @clauses where *.elems == 1, @bind) {
        (@clauses[0], @bind);
    }

    multi method join-sql-clauses(Str:D $logic, @clauses where *.elems == 0, @bind) {
        Empty
    }

    method sqlcase(Str $sql) returns Str {
        $!case eq 'lower' ?? $sql.lc !! $sql.uc;
    }


=begin comment
#======================================================================
# VALUES, GENERATE, AUTOLOAD
#======================================================================

# LDNOTE: original code from nwiger, didn't touch code in that section
# I feel the AUTOLOAD stuff should not be the default, it should
# only be activated on explicit demand by user.

sub values {
    my $self = shift;
    my $data = shift || return;
    puke "Argument to ", $?PACKAGE, "-\>values must be a \\%hash"
        unless ref $data eq 'HASH';

    my @all_bind;
    for ( sort keys %$data ) -> $k {
        my $v = $data.{'$k'};
        $self._SWITCH_refkind($v, {
          ARRAYREF => sub {
            if ($self.{'array_datatypes'}) { # array datatype
              push @all_bind, $self._bindtype($k, $v);
            }
            else {                          # literal SQL with bind
              my ($sql, @bind) = @$v;
              $self._assert_bindval_matches_bindtype(@bind);
              push @all_bind, @bind;
            }
          },
          ARRAYREFREF => sub { # literal SQL with bind
            my ($sql, @bind) = @$($v);
            $self._assert_bindval_matches_bindtype(@bind);
            push @all_bind, @bind;
          },
          SCALARREF => sub {  # literal SQL without bind
          },
          SCALAR_or_UNDEF => sub {
            push @all_bind, $self._bindtype($k, $v);
          },
        });
    }

    return @all_bind;
}


# not sure what this is for anymore
sub generate {
    my $self  = shift;

    my (@sql, @sqlq, @sqlv);

    for (@_) {
        my $ref = ref $_;
        if ($ref eq 'HASH') {
            for (sort keys %$_) -> $k {
                my $v = $_.{'$k'};
                my $r = ref $v;
                my $label = $self._quote($k);
                if ($r eq 'ARRAY') {
                    # literal SQL with bind
                    my ($sql, @bind) = @$v;
                    $self._assert_bindval_matches_bindtype(@bind);
                    push @sqlq, "$label = $sql";
                    push @sqlv, @bind;
                } elsif ($r eq 'SCALAR') {
                    # literal SQL without bind
                    push @sqlq, "$label = $$v";
                } else {
                    push @sqlq, "$label = ?";
                    push @sqlv, $self._bindtype($k, $v);
                }
            }
            push @sql, $self._sqlcase('set'), join ', ', @sqlq;
        } elsif ($ref eq 'ARRAY') {
            # unlike insert(), assume these are ONLY the column names, i.e. for SQL
            for (@$_) -> $v {
                my $r = ref $v;
                if ($r eq 'ARRAY') {   # literal SQL with bind
                    my ($sql, @bind) = @$v;
                    $self._assert_bindval_matches_bindtype(@bind);
                    push @sqlq, $sql;
                    push @sqlv, @bind;
                } elsif ($r eq 'SCALAR') {  # literal SQL without bind
                    # embedded literal SQL
                    push @sqlq, $$v;
                } else {
                    push @sqlq, '?';
                    push @sqlv, $v;
                }
            }
            push @sql, '(' ~ join(', ', @sqlq) ~ ')';
        } elsif ($ref eq 'SCALAR') {
            # literal SQL
            push @sql, $$_;
        } else {
            # strings get case twiddled
            push @sql, $self._sqlcase($_);
        }
    }

    my $sql = join ' ', @sql;

    # this is pretty tricky
    # if ask for an array, return ($stmt, @bind)
    # otherwise, s/?/shift @sqlv/ to put it inline
    if (wantarray) {
        return ($sql, @sqlv);
    } else {
        1 while $sql ~~ s:e:P5/\?/my $d = shift(@sqlv);
                             ref $d ? $d->[1] : $d/;
        return $sql;
    }
}

=end comment


}


# vim: expandtab shiftwidth=4 ft=perl6