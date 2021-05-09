package Zapp::Formula;

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

L<Zapp::Task>, L<Zapp>

=cut

use Mojo::Base -base, -signatures;
use Zapp::Util qw( get_path_from_data );
use List::Util qw( any all pairs );

# XXX: binops, functions, and grammar should all be attributes so that
# they can be configured per-instance
our %BINOPS = (
    '+' => sub { $_[0] + $_[1] },
    '-' => sub { $_[0] - $_[1] },
    '*' => sub { $_[0] * $_[1] },
    '/' => sub { $_[0] / $_[1] },
    '^' => sub { $_[0] ** $_[1] },
    '&' => sub { $_[0] . $_[1] },
    # XXX: Logical binops need to detect numbers vs. strings and change
    # comparisons
    '=' => sub { $_[0] eq $_[1] },
    '>' => sub { $_[0] gt $_[1] },
    '<' => sub { $_[0] lt $_[1] },
    '>=' => sub { $_[0] ge $_[1] },
    '<=' => sub { $_[0] le $_[1] },
    '<>' => sub { $_[0] ne $_[1] },
);

our %FUNCTIONS = (
    ### Logic functions
    TRUE => \&_func_true,
    FALSE => \&_func_false,
    NOT => \&_func_not,
    IF => \&_func_if,
    IFS => \&_func_ifs,
    AND => \&_func_and,
    OR => \&_func_or,
    XOR => \&_func_xor,
    EVAL => \&_func_eval,
    ### Text functions
    # Case manipulation
    LOWER => sub( $f, $str ) { lc $str },
    UPPER => sub( $f, $str ) { uc $str },
    PROPER => sub( $f, $str ) { ( lc $str ) =~ s/(?:^|[^a-zA-Z'])([a-z])/uc $1/er },
    # Substrings
    LEFT => sub( $f, $str, $len ) { substr $str, 0, $len },
    RIGHT => sub( $f, $str, $len ) { substr $str, -$len },
);

my ( @result, @term, @args, @binop, @call, @array, @hash, @var, $depth, $expected, $failed_at );
our $GRAMMAR = qr{
    (?(DEFINE)
        (?<EXPR>
            # Expressions can recurse, so we need to use a stack. When
            # we recurse, we must take the result off the stack and save
            # it until we can put it back on the stack (somewhere)
            (?{ $depth++ })(?>
            \s*
            (?:
                # Terminator first, to escape infinite loops
                (?> (?&TERM) ) (?! (?&OP) | \( ) \s*
                (*COMMIT) (?{ push @result, pop @term })
                # If there is more to match, it must've been an attempt
                # at an operator
                (?{ $expected = 'Expected operator'; $failed_at = pos() })
            |
                (?> (?&CALL) ) (?! (?&OP) ) \s*
                (*COMMIT) (?{ push @result, [ call => @{ pop @call } ] })
                # If there is more to match, it must've been an attempt
                # at an operator
                (?{ $expected = 'Expected operator'; $failed_at = pos() })
            |
                (?> (?&ARRAY) ) (?! (?&OP) )
                (*COMMIT) (?{ push @result, [ array => @{ pop @array } ] })
            |
                (?> (?&HASH) ) (?! (?&OP) )
                (*COMMIT) (?{ push @result, [ hash => @{ pop @hash } ] })
            |
                (?{ push @binop, [] })
                (?>
                    (?> (?&CALL) )
                    (?{ push @{ $binop[-1] }, [ call => @{ pop @call } ] })
                |
                    (?> (?&TERM) )
                    (?{ push @{ $binop[-1] }, [ @{ pop @term } ] })
                )
                (*COMMIT) (?{ $expected = 'Expected operator'; $failed_at = pos() })
                (?<op> (?&OP) ) \s*
                (*COMMIT) (?{ $expected = 'Expected expression'; $failed_at = pos() })
                (?> (?&EXPR) )
                (?{ push @result, [ binop => $+{op}, @{ pop @binop }, pop @result ] })
            |
                # Characters that cannot be used to start a term, call,
                # array, or hash
                [^a-zA-Z0-9\."\-\[\{]
                (*FAIL)
            )
            )(?{ $depth-- })
        )
        (?<OP>(?> @{[ join '|', map quotemeta, keys %BINOPS ]} ))
        (?<CALL>(?>
            (?&VAR)
            (?{ push @call, [ [ var => @var ] ]; @var = () })
            \s* \( \s*
                (?>
                    (?{ push @args, [] })
                    (?>
                        (?&EXPR)
                        (?{ push @{ $args[-1] }, pop @result })
                    )?
                    (?:
                        \s* , \s* (?> (?&EXPR) )
                        (?{ push @{ $args[-1] }, pop @result })
                    )*
                )
                \s* (*COMMIT)
                (?{ $expected = 'Could not find end parenthesis'; $failed_at = pos() })
            \) \s*
            (?{ push $call[-1]->@*, @{ pop @args } })
        ))
        (?<ARRAY>(?>
            \[ \s*
                (?{ push @array, [] })
                (?:
                    (?> (?&EXPR) ) \s* ,? \s*
                    (?{ push @{ $array[-1] }, pop @result })
                )*
            \] \s*
        ))
        (?<HASH>(?>
            \{ \s*
                (?{ push @hash, [] })
                (?:
                    (?> (?<key> (?&STRING) ) ) \s* : \s*
                    (?> (?&EXPR) ) \s* ,? \s*
                    (?{ push @{ $hash[-1] }, [ $+{'key'}, pop @result ] })
                )*
            \} \s*
        ))
        (?<TERM>(?>
            (?:
                (?<string> (?&STRING) )
                (?{ push @term, [ %+{'string'} ] })
            |
                (?<number> (?&NUMBER) )
                (?{ push @term, [ %+{'number'} ] })
            |
                (?&VAR)
                (?{ push @term, [ var => @var ]; @var = () })
            )
            \s*
        ))
        (?<VAR>
            (?<word> [a-zA-Z][a-zA-Z0-9_]+ ) \s*
            (?{ push @var, $+{word} })
            (?: \. \s* (?&VAR) )*+
        )
        (?<STRING>
            "
            (?>
                [^"\\]*+  (?: \\" [^"\\]*+ )*+
            )
            (*COMMIT) (?{ $expected = 'Could not find closing quote for string'; $failed_at = pos() })
            "
        )
        (?<NUMBER> -? \d+ %? | -? \d* \. \d+ %? )
    )
}xms;

has context => sub { {} };

# XXX: Strings that look like money amounts can be coerced into numbers
# XXX: Strings that look like dates can be coerced into dates
#       ... Or maybe not, since that's one of the biggest complaints
#       about Excel. Though, that might just refer to the
#       auto-formatting thing, which we will not be doing.

# Does not expect `=` prefix
sub parse( $self, $expr ) {
    @result = ();
    $depth = 0;
    $expected = '';
    $failed_at = 0;
    unless ( $expr =~ /${GRAMMAR}^(?&EXPR)$/ ) {
        # XXX: Parse error handling. DCONWAY has numerous
        # (?{ $expected = '...'; $failed_at = pos() }) in his
        # Keyword::Declare grammar. If parsing stops, the last value in
        # those vars is used to show an error message.
        $failed_at = 'end of input' if $failed_at >= length $expr;
        die "Syntax error: $expected at $failed_at.\n";
    }
    return $result[0];
}

# Does not expect `=` prefix
sub eval( $self, $expr, $context={} ) {
    $self->context( $context );
    my $tree = $self->parse( $expr );
    my $handle = sub( $tree ) {
        if ( $tree->[0] eq 'string' ) {
            # XXX: strip slashes
            my $string = substr $tree->[1], 1, -1;
            $string =~ s/\\(?!\\)//g;
            return $string;
        }
        if ( $tree->[0] eq 'number' ) {
            return $tree->[1];
        }
        if ( $tree->[0] eq 'var' ) {
            my $var = join '.', $tree->@[1..$#$tree];
            my $context = $self->context;
            return ref $context eq 'CODE' ? $context->( $var )
                : get_path_from_data( $var, $context )
                ;
        }
        if ( $tree->[0] eq 'call' ) {
            my $name = join '.', $tree->[1]->@[1..$tree->[1]->$#*];
            my @args = map { __SUB__->( $_ ) } @{$tree}[2 .. $#{$tree}];
            return $FUNCTIONS{ $name }->( $self, @args );
        }
        if ( $tree->[0] eq 'binop' ) {
            my $op = $tree->[1];
            my $left = __SUB__->( $tree->[2] );
            my $right = __SUB__->( $tree->[3] );
            return $BINOPS{ $op }->( $left, $right );
        }
        die "Unknown parse result: $tree->[0]";
    };
    my $result = $handle->( $tree );
    return $result;
}

=method resolve

    my $data = $f->resolve( $data, $context );

Resolve all formulas in the data structure C<$data> and return a new data structure
with the resolved values. Formulas are strings that begin with C<=>. Use C<==> to escape
parsing.

    # { val => 1, str => '=num' }
    $f->resolve( { val => '=num', str => '==num' }, { num => 1 } );

=cut

sub resolve( $self, $data, $context={} ) {
    return ref $data eq 'ARRAY' ? [ map { $self->resolve( $_, $context ) } @$data ]
        : ref $data eq 'HASH' ? { map { $_ => $self->resolve( $data->{ $_ }, $context ) } keys %$data }
        : !ref $data && $data =~ /^=(?!=)/ ? $self->eval( substr( $data, 1 ), $context )
        : $data =~ s/^==/=/r;
}

=head1 FUNCTIONS

XXX: Add real-world examples of usage of all functions

=cut

# NOTE: Arrange all functions in alphabetical order inside their
# category

=head2 Logic/Control Functions

=head3 AND

    =AND( <expression>... )

Returns C<TRUE> if all expressions are true.

=cut

sub _func_and( $f, @exprs ) {
    return ( all { !!$_ } @exprs ) ? _func_true($f) : _func_false($f);
}

=head3 EVAL

    =EVAL( <string> )

Evaluate the string as a formula and return the result. The string must
not begin with an C<=>.

=cut

sub _func_eval( $f, $expr ) {
    # XXX: This context attribute is a bad way of doing things, but we
    # need some way for functions to get the context, or values from the
    # context...
    return $f->eval( $expr, $f->context );
}

=head3 FALSE

    =FALSE()

Returns a false value.

=cut

sub _func_false( $f ) {
    return Mojo::JSON->false;
}

=head3 IF

    =IF( <expression>, <true_result>, <false_result> )

Evaluate the expression in C<expression> and return C<true_result> if
the condition is true, or C<false_result> if the condition is false.

=cut

sub _func_if( $f, $expr, $true_result, $false_result ) {
    return $expr ? $true_result : $false_result;
}

=head3 IFS

    =IFS( <expression>, <result>, ..., <default_result> )

Evaluate each expression and return its corresponding result if the
expression is true. Return C<default_result> if no condition is true.

=cut

sub _func_ifs( $f, @args ) {
    my $default = pop @args;
    for my $pair ( pairs @args ) {
        return $pair->[1] if $pair->[0];
    }
    return $default;
}

=head3 NOT

    =NOT( <expression> )

Returns C<TRUE> if the expression is true, C<FALSE> otherwise.

=cut

sub _func_not( $f, $expr ) {
    return !!$expr ? _func_false($f) : _func_true($f);
}

=head3 OR

    =OR( <expression>... )

Returns C<TRUE> if one expression is true.

=cut

sub _func_or( $f, @exprs ) {
    return ( any { !!$_ } @exprs ) ? _func_true($f) : _func_false($f);
}

=head3 TRUE

    =TRUE()

Returns a true value.

=cut

sub _func_true( $f ) {
    return Mojo::JSON->true;
}

=head3 XOR

    =XOR( <expression>... )

Returns C<TRUE> if one and only one expression is true.

=cut

sub _func_xor( $f, @exprs ) {
    return ( grep { !!$_ } @exprs ) == 1 ? _func_true($f) : _func_false($f);
}

#=head2 Text Functions

#=cut

#=head2 Date/Time Functions

#=cut

1;
