
=head1 DESCRIPTION

This tests the Zapp::Type::Enum class

=cut

use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Zapp;
use Mojo::DOM;
use Zapp::Type::Enum;

my $t = Test::Zapp->new( 'Zapp' );
my $type = Zapp::Type::Enum->new( [qw( foo bar baz )] );
$t->app->zapp->add_type( enum => $type );

subtest 'input_field' => sub {
    subtest 'values only' => sub {
        my $c = $t->app->build_controller;
        my $html = $type->input_field( $c, 'foo' );
        my $dom = Mojo::DOM->new( $html );

        is $dom->children->[0]->tag, 'select', 'field is a select tag'
            or diag explain $dom->children->[0];
        ok $dom->at( 'option[value=foo]' ), 'value foo exists';
        is $dom->at( 'option[value=foo]' )->content, 'foo', 'value foo label is correct';
        ok $dom->at( 'option[selected]' ), 'selected option exists';
        is $dom->at( 'option[selected]' )->attr( 'value' ), 'foo', 'selected value is correct';
        ok $dom->at( 'option[value=bar]' ), 'value bar exists';
        is $dom->at( 'option[value=bar]' )->content, 'bar', 'value bar label is correct';
        ok $dom->at( 'option[value=baz]' ), 'value baz exists';
        is $dom->at( 'option[value=baz]' )->content, 'baz', 'value baz label is correct';
    };

    subtest 'value/label pairs' => sub {
        my $type = Zapp::Type::Enum->new( [ map { [ uc $_, $_ ] } qw( foo bar baz ) ] );
        $t->app->zapp->add_type( ENUM => $type );

        my $c = $t->app->build_controller;
        my $html = $type->input_field( $c, 'foo' );
        my $dom = Mojo::DOM->new( $html );

        is $dom->children->[0]->tag, 'select', 'field is a select tag'
            or diag explain $dom->children->[0];
        ok $dom->at( 'option[value=foo]' ), 'value foo exists';
        is $dom->at( 'option[value=foo]' )->content, 'FOO', 'value foo label is correct';
        ok $dom->at( 'option[selected]' ), 'selected option exists';
        is $dom->at( 'option[selected]' )->attr( 'value' ), 'foo', 'selected value is correct';
        ok $dom->at( 'option[value=bar]' ), 'value bar exists';
        is $dom->at( 'option[value=bar]' )->content, 'BAR', 'value bar label is correct';
        ok $dom->at( 'option[value=baz]' ), 'value baz exists';
        is $dom->at( 'option[value=baz]' )->content, 'BAZ', 'value baz label is correct';
    };
};

subtest 'plan_input' => sub {
    my $c = $t->app->build_controller;
    my $type_value = $type->plan_input( $c, 'foo' );
    is $type_value, 'foo', 'plan_input returns value';

    subtest 'invalid input' => sub {
        eval { $type->plan_input( $c, 'INVALID' ) };
        ok $@, 'invalid value dies';
    };
};

subtest 'run_input' => sub {
    my $c = $t->app->build_controller;
    my $type_value = $type->run_input( $c, 'foo' );
    is $type_value, 'foo', 'plan_input returns value';

    subtest 'invalid input' => sub {
        eval { $type->run_input( $c, 'INVALID' ) };
        ok $@, 'invalid value dies';
    };
};

subtest 'task_input' => sub {
    my $task_value = $type->task_input( 'foo' );
    is $task_value, 'foo', 'task_input returns value';
};

subtest 'task_output' => sub {
    my $type_value = $type->task_output( 'foo' );
    is $type_value, 'foo', 'task_output returns value';

    subtest 'invalid value' => sub {
        eval { $type->task_output( 'INVALID' ) };
        ok $@, 'invalid value dies';
    };
};

done_testing;
