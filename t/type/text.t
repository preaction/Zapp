
=head1 DESCRIPTION

This tests the Zapp::Type::Text class

=cut

use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Zapp;
use Mojo::DOM;
use Zapp::Type::Text;

my $t = Test::Zapp->new( 'Zapp' );
my $type = Zapp::Type::Text->new;
$t->app->zapp->add_type( text => $type );

subtest 'input_field' => sub {
    subtest 'values only' => sub {
        my $c = $t->app->build_controller;
        my $html = $type->input_field( $c, 'foo' );
        my $dom = Mojo::DOM->new( $html );

        is $dom->children->[0]->tag, 'input', 'field is an input tag'
            or diag explain $dom->children->[0];
        is $dom->at( 'input' )->attr( 'type' ), 'text', 'input tag type "text"';
        is $dom->at( 'input' )->attr( 'value' ), 'foo', 'input tag value correct';
    };
};

subtest 'plan_input' => sub {
    my $c = $t->app->build_controller;
    my $type_value = $type->plan_input( $c, { plan_id => 1 }, 'foo' );
    is $type_value, 'foo', 'plan_input returns value';
};

subtest 'run_input' => sub {
    my $c = $t->app->build_controller;
    my $type_value = $type->run_input( $c, { run_id => 1 }, 'foo' );
    is $type_value, 'foo', 'plan_input returns value';
};

subtest 'task_input' => sub {
    my $task_value = $type->task_input( { run_id => 1 }, { task_id => 1 }, 'foo' );
    is $task_value, 'foo', 'task_input returns value';
};

subtest 'task_output' => sub {
    my $type_value = $type->task_output( { run_id => 1 }, { task_id => 1 }, 'foo' );
    is $type_value, 'foo', 'task_output returns value';
};

done_testing;
