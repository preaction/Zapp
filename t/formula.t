
=head1 DESCRIPTION

This tests the Zapp::Formula class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Mojo;
use Test::More;
use Zapp::Formula;

my $f = Zapp::Formula->new;

subtest 'parse' => sub {
    my $tree = $f->parse( q{"string"} );
    is_deeply $tree, [ string => q{"string"} ], 'string parsed correctly';

    $tree = $f->parse( q{foo.bar} );
    is_deeply $tree, [ var => q{foo.bar} ], 'var parsed correctly';

    $tree = $f->parse( q{UPPER("string")} );
    is_deeply $tree, [ call => UPPER => [ string => q{"string"} ] ],
        'function call parsed correctly';

    $tree = $f->parse( q{LEFT(LOWER(Foo),2)} );
    is_deeply $tree,
        [
            call => 'LEFT',
            [
                call => 'LOWER',
                [
                    var => 'Foo',
                ],
            ],
            [
                number => 2,
            ],
        ],
        'function call with function call as argument parsed correctly';

    subtest 'unclosed string literal' => sub {
        my $tree;
        eval { $tree = $f->parse( q{UPPER(Foo&"Bar)} ) };
        ok $@, 'parse dies for syntax error';
        # The end parenthesis is considered part of the string, so
        # this error is found at the end of input.
        # XXX: "Might be an unclosed string starting at ..."
        like $@, qr{Could not find closing quote for string at end of input},
            'error message is correct';
        ok !$tree, 'nothing returned' or diag explain $tree;
    };

    subtest 'binop missing right-hand side' => sub {
        my $tree;
        eval { $tree = $f->parse( q{UPPER(LOWER(Foo)&)} ) };
        ok $@, 'parse dies for syntax error';
        like $@, qr{Expected variable, number, string, or function call at 17},
            'error message is correct';
        ok !$tree, 'nothing returned' or diag explain $tree;
    };

    subtest 'illegal character in variable' => sub {
        my $tree;
        eval { $tree = $f->parse( q{Bar:baz} ) };
        ok $@, 'parse dies for syntax error';
        like $@, qr{Expected operator at 3},
            'error message is correct';
        ok !$tree, 'nothing returned' or diag explain $tree;
    };

    subtest 'function missing close parens' => sub {
        my $tree;
        eval { $tree = $f->parse( q{UPPER(bar} ) };
        ok $@, 'parse dies for syntax error';
        like $@, qr{Could not find end parenthesis at end of input},
            'error message is correct';
        ok !$tree, 'nothing returned' or diag explain $tree;
    };

};

subtest 'eval' => sub {
    my $context = {
        Hash => {
            Key => 'success',
        },
        Str => 'string',
    };

    my $result = $f->eval( q{"string"}, $context );
    is $result, 'string', 'string literal';

    $result = $f->eval( q{"hello, \"doug\""}, $context );
    is $result, 'hello, "doug"', 'string literal with escaped quotes';

    $result = $f->eval( q{Hash.Key}, $context );
    is $result, 'success', 'variable lookup from context';

    $result = $f->eval( q{UPPER("foo")}, $context );
    is $result, 'FOO', 'function call';

    $result = $f->eval( q{Str&"Bar"}, $context );
    is $result, 'stringBar', 'binary operator';

    $result = $f->eval( q{UPPER("foo"&Str)}, $context );
    is $result, 'FOOSTRING', 'function call takes binary operator expr as argument';

    $result = $f->eval( q{LEFT("foo",2)}, $context );
    is $result, 'fo', 'function call with multiple arguments';

    $result = $f->eval( q{LEFT(UPPER(Str),2)}, $context );
    is $result, 'ST', 'function call with function call as argument';

    $result = $f->eval( q{LOWER("FOO")&UPPER(Str)}, $context );
    is $result, "fooSTRING", 'binary operator with function call as operands';
};

done_testing;

