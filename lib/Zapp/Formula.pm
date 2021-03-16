package Zapp::Formula;

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

L<Zapp::Task>, L<Zapp>

=cut

use Mojo::Base -base, -signatures;
use Zapp::Util qw( get_path_from_data );

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
    ### Text functions
    # Case manipulation
    LOWER => sub( $str ) { lc $str },
    UPPER => sub( $str ) { uc $str },
    PROPER => sub( $str ) { ( lc $str ) =~ s/(?:^|[^a-zA-Z'])([a-z])/uc $1/er },
    # Substrings
    LEFT => sub( $str, $len ) { substr $str, 0, $len },
    RIGHT => sub( $str, $len ) { substr $str, -$len },
);

my ( @result, @term, @args, @binop, @call, @array, @hash, $depth, $expected, $failed_at );
our $GRAMMAR = qr{
    (?(DEFINE)
        (?<EXPR>
            # Expressions can recurse, so we need to use a stack. When
            # we recurse, we must take the result off the stack and save
            # it until we can put it back on the stack (somewhere)
            (?{ $depth++ })(?>
            (?:
                # Terminator first, to escape infinite loops
                (?> (?&TERM) ) (?! (?&OP) | \( )
                (?{ push @result, pop @term })
                (?{ $expected = 'Expected operator'; $failed_at = pos() })
            |
                (?> (?&CALL) ) (?! (?&OP) )
                (?{ push @result, [ call => @{ pop @call } ] })
                (?{ $expected = 'Expected operator'; $failed_at = pos() })
            |
                (?> (?&ARRAY) ) (?! (?&OP) )
                (?{ push @result, [ array => @{ pop @array } ] })
            |
                (?> (?&HASH) ) (?! (?&OP) )
                (?{ push @result, [ hash => @{ pop @hash } ] })
            |
                (?{ push @binop, [] })
                (?>
                    (?> (?&CALL) )
                    (?{ push @{ $binop[-1] }, [ call => @{ pop @call } ] })
                |
                    (?> (?&TERM) )
                    (?{ push @{ $binop[-1] }, [ @{ pop @term } ] })
                )
                (?<op> (?&OP) )
                (?{ $expected = 'Expected variable, number, string, or function call'; $failed_at = pos() })
                (?>
                    (?> (?&CALL) )
                    (?{ push @{ $binop[-1] }, [ call => @{ pop @call } ] })
                |
                    (?> (?&TERM) )
                    (?{ push @{ $binop[-1] }, [ @{ pop @term } ] })
                )
                (?{ push @result, [ binop => $+{op}, @{ pop @binop } ] })
            )
            )(?{ $depth-- })
        )
        (?<OP>(?> @{[ join '|', map quotemeta, keys %BINOPS ]} ))
        (?<CALL>(?>
            (?<name> (?&VAR) )
            \(
                (?>
                    (?{ push @args, [] })
                    (?> (?&EXPR) )
                    (?{ push @{ $args[-1] }, pop @result })
                    (?:
                        , (?> (?&EXPR) )
                        (?{ push @{ $args[-1] }, pop @result })
                    )*
                )
                (?{ $expected = 'Could not find end parenthesis'; $failed_at = pos() })
            \)
            (?{ push @call, [ $+{name}, @{ pop @args } ] })
        ))
        (?<ARRAY>(?>
            \[
                (?{ push @array, [] })
                (?:
                    (?> (?&EXPR) ) ,?
                    (?{ push @{ $array[-1] }, pop @result })
                )*
            \]
        ))
        (?<HASH>(?>
            \{
                (?{ push @hash, [] })
                (?:
                    (?> (?<key> (?&STRING) ) ) :
                    (?> (?&EXPR) ) ,?
                    (?{ push @{ $hash[-1] }, [ $+{'key'}, pop @result ] })
                )*
            \}
        ))
        (?<TERM>(?>
            (?:
                (?<string> (?&STRING) )
                (?{ push @term, [ %+{'string'} ] })
            |
                (?<number> (?&NUMBER) )
                (?{ push @term, [ %+{'number'} ] })
            |
                (?<var> (?&VAR) )
                (?{ push @term, [ %+{'var'} ] })
            )
        ))
        (?<VAR> [a-zA-Z][a-zA-Z0-9_.]* )
        (?<STRING>
            "
            (?>
                [^"\\]*+  (?: \\" [^"\\]*+ )*+
            )
            (?{ $expected = 'Could not find closing quote for string'; $failed_at = pos() })
            "
        )
        (?<NUMBER> -? \d+ %? | -? \d* \. \d+ %? )
    )
}xms;

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
            return ref $context eq 'CODE' ? $context->( $tree->[1] )
                : get_path_from_data( $tree->[1], $context )
                ;
        }
        if ( $tree->[0] eq 'call' ) {
            my $name = $tree->[1];
            my @args = map { __SUB__->( $_ ) } @{$tree}[2 .. $#{$tree}];
            return $FUNCTIONS{ $name }->( @args );
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

1;
