
=head1 DESCRIPTION

This tests the Zapp::Type::File class

=cut

use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Zapp;
use Mojo::DOM;
use Mojo::File qw( path tempfile tempdir );
use Zapp::Type::File;

my $t = Test::Zapp->new( 'Zapp' );
my $type = Zapp::Type::File->new( app => $t->app );
$t->app->zapp->add_type( file => $type );
my $temp = tempdir();
$t->app->home( $temp );

subtest 'input_field' => sub {
    my $c = $t->app->build_controller;
    my $html = $type->input_field( $c, 'foo' );
    my $dom = Mojo::DOM->new( $html );

    my $field = $dom->children->[0];
    is $field->tag, 'input', 'field is an input tag'
        or diag explain $field;
    is $field->attr( 'value' ), 'foo', 'field value correct'
        or diag explain $field;
};

subtest 'plan_input' => sub {
    my $c = $t->app->build_controller;
    my $upload = Mojo::Upload->new(
        filename => 'foo.txt',
        asset => Mojo::Asset::Memory->new->add_chunk( 'Hello, World!' ),
        name => 'input[0].value',
    );
    my $type_value = $type->plan_input( $c, { plan_id => 1 }, $upload );
    is $type_value, 'plan/1/input/0/foo.txt',
        'form_input returns path';
    my $file = $temp->child( 'uploads', split m{/}, $type_value );
    ok -e $file, 'file exists';
    is $file->slurp, 'Hello, World!', 'file content is correct';

    subtest 'no default' => sub {
        my $upload = Mojo::Upload->new(
            filename => '',
            asset => Mojo::Asset::Memory->new->add_chunk( '' ),
            name => 'input[0].value',
        );
        my $type_value = $type->plan_input( $c, { plan_id => 1 }, $upload );
        is $type_value, undef, 'blank value is undef';
    };
};

subtest 'run_input' => sub {
    my $c = $t->app->build_controller;
    my $upload = Mojo::Upload->new(
        filename => 'foo.txt',
        asset => Mojo::Asset::Memory->new->add_chunk( 'Hello, World!' ),
        name => 'input[0].value',
    );
    my $type_value = $type->run_input( $c, { run_id => 1 }, $upload );
    is $type_value, 'run/1/input/0/foo.txt',
        'form_input returns path';
    my $file = $temp->child( 'uploads', split m{/}, $type_value );
    ok -e $file, 'file exists';
    is $file->slurp, 'Hello, World!', 'file content is correct';
};

subtest 'task_input' => sub {
    my $type_value = 'task_input';
    my $input_file = $temp->child( uploads => $type_value )->spurt( 'Goodbye, World!' );
    my $task_value = $type->task_input( { run_id => 1 }, { task_id => 1 }, $type_value );
    isa_ok $task_value, 'Mojo::File';
    is $task_value, $t->app->home->child( uploads => $type_value ),
        'task_value path is correct';
};

subtest 'task_output' => sub {
    my $tmp = tempfile()->spurt( 'Goodbye, World!' );
    my $task_value = "$tmp";
    my $type_value = $type->task_output( { run_id => 1 }, { task_id => 1 }, $task_value );
    is $type_value, 'run/1/task/1/' . $tmp->basename,
        'type_value is correct';
    my $file = $t->app->home->child(qw( uploads run 1 task 1 ), $tmp->basename );
    ok -e $file, 'file exists';
    is $file->slurp, 'Goodbye, World!', 'file content is correct';
};

done_testing;
