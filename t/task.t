
=head1 DESCRIPTION

This tests the base Zapp::Task class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Mojo;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Task;

my $mysqld = Test::mysqld->new(
    my_cnf => {
        # Needed for Minion::Backend::mysql
        log_bin_trust_function_creators => 1,
    },
) or plan skip_all => $Test::mysqld::errstr;

my $t = Test::Mojo->new( 'Zapp', {
    backend => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
    minion => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
} );

subtest 'eval_expr' => sub {
    my $task = Zapp::Task->new(
        _context => {
            Hash => {
                Key => 'success',
            },
            Str => 'string',
        },
    );

    my $result = $task->eval_expr( q{"string"} );
    is $result, 'string', 'string literal';

    $result = $task->eval_expr( q{"hello, \"doug\""} );
    is $result, 'hello, "doug"', 'string literal with escaped quotes';

    $result = $task->eval_expr( q{Hash.Key} );
    is $result, 'success', 'variable lookup from context';

    $result = $task->eval_expr( q{UPPER("foo")} );
    is $result, 'FOO', 'function call';

    $result = $task->eval_expr( q{Str&"Bar"} );
    is $result, 'stringBar', 'binary operator';

    $result = $task->eval_expr( q{UPPER("foo"&Str)} );
    is $result, 'FOOSTRING', 'function call takes binary operator expr as argument';

    $result = $task->eval_expr( q{LEFT("foo",2)} );
    is $result, 'fo', 'function call with multiple arguments';

    $result = $task->eval_expr( q{LEFT(UPPER(Str),2)} );
    is $result, 'ST', 'function call with function call as argument';

    $result = $task->eval_expr( q{LOWER("FOO")&UPPER(Str)} );
    is $result, "fooSTRING", 'binary operator with function call as operands';

    subtest 'parse_expr' => sub {
        my $tree = Zapp::Task::parse_expr( q{"string"} );
        is_deeply $tree, [ string => q{"string"} ], 'string parsed correctly';

        $tree = Zapp::Task::parse_expr( q{foo.bar} );
        is_deeply $tree, [ var => q{foo.bar} ], 'var parsed correctly';

        $tree = Zapp::Task::parse_expr( q{UPPER("string")} );
        is_deeply $tree, [ call => UPPER => [ string => q{"string"} ] ],
            'function call parsed correctly';

        $tree = Zapp::Task::parse_expr( q{LEFT(LOWER(Foo),2)} );
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
            eval { $tree = Zapp::Task::parse_expr( q{UPPER(Foo&"Bar)} ) };
            ok $@, 'parse expr dies for syntax error';
            # The end parenthesis is considered part of the string, so
            # this error is found at the end of input.
            # XXX: "Might be an unclosed string starting at ..."
            like $@, qr{Could not find closing quote for string at end of input},
                'error message is correct';
            ok !$tree, 'nothing returned' or diag explain $tree;
        };

        subtest 'binop missing right-hand side' => sub {
            my $tree;
            eval { $tree = Zapp::Task::parse_expr( q{UPPER(LOWER(Foo)&)} ) };
            ok $@, 'parse expr dies for syntax error';
            like $@, qr{Expected variable, number, string, or function call at 17},
                'error message is correct';
            ok !$tree, 'nothing returned' or diag explain $tree;
        };

        subtest 'illegal character in variable' => sub {
            my $tree;
            eval { $tree = Zapp::Task::parse_expr( q{Bar:baz} ) };
            ok $@, 'parse expr dies for syntax error';
            like $@, qr{Expected operator at 3},
                'error message is correct';
            ok !$tree, 'nothing returned' or diag explain $tree;
        };

        subtest 'function missing close parens' => sub {
            my $tree;
            eval { $tree = Zapp::Task::parse_expr( q{UPPER(bar} ) };
            ok $@, 'parse expr dies for syntax error';
            like $@, qr{Could not find end parenthesis at end of input},
                'error message is correct';
            ok !$tree, 'nothing returned' or diag explain $tree;
        };

    };

};

subtest 'execute' => sub {
    my $plan = $t->app->create_plan({
        name => 'Deliver a package',
        description => 'To a dangerous place',
        tasks => [
            {
                name => 'Plan trip',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    vars => [
                        { name => 'dest', value => '=destination' },
                    ],
                    script => 'echo $dest',
                }),
            },
            {
                name => 'Deliver package',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    vars => [
                        { name => 'dest', value => '=destination' },
                    ],
                    script => 'echo Certain Doom on $dest',
                }),
            },
        ],
        inputs => [
            {
                name => 'destination',
                type => 'string',
                description => 'Where to send the crew to their doom',
                value => encode_json( 'Chapek 9' ),
            },
        ],
    });

    subtest 'success' => sub {
        my $input = {
            destination => {
                type => 'string',
                value => 'Nude Beach Planet',
            },
            unused_value => {
                type => 'string',
                value => 'Should be passed through',
            },
        };

        my $run = $t->app->enqueue( $plan->{plan_id}, $input );
        my @tasks = @{ $run->{tasks} };

        $run = $t->app->yancy->get( zapp_runs => $run->{run_id} );
        is_deeply
            {
                %$run,
                input => decode_json( $run->{input} ),
            },
            {
                $run->%{qw( run_id created )},
                $plan->%{qw( plan_id name description )},
                input => {
                    destination => {
                        type => 'string',
                        value => 'Nude Beach Planet',
                    },
                    unused_value => {
                        type => 'string',
                        value => 'Should be passed through',
                    },
                },
                started => undef,
                finished => undef,
                state => 'inactive',
            },
            'database run is correct';

        # Check jobs created correctly
        my @got_tasks = $t->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} }, { order_by => 'task_id' } );
        is_deeply
            {
                $got_tasks[0]->%*,
                input => decode_json( $got_tasks[0]{input} ),
            },
            {
                $got_tasks[0]->%{qw( job_id task_id )},
                input => decode_json( $plan->{tasks}[0]{input} ),
                plan_task_id => $plan->{tasks}[0]{task_id},
                $plan->{tasks}[0]->%{qw( name description class )},
                run_id => $run->{run_id},
                state => 'inactive',
                output => undef,
            },
            'first job run entry is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
            },
            {
                $got_tasks[1]->%{qw( job_id task_id )},
                plan_task_id => $plan->{tasks}[1]{task_id},
                $plan->{tasks}[1]->%{qw( name description class )},
                input => decode_json( $plan->{tasks}[1]{input} ),
                run_id => $run->{run_id},
                state => 'inactive',
                output => undef,
            },
            'second job run entry is correct';

        subtest 'run first job' => sub {
            my $worker = $t->app->minion->worker->register;
            my $job = $worker->dequeue;
            my $e = $job->execute;
            ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;
            is_deeply $job->args,
                [
                    {
                        vars => [
                            { name => 'dest', value => 'Nude Beach Planet' },
                        ],
                        script => 'echo $dest',
                    },
                ],
                'minion job args are interpolated input';

            $run = $t->app->yancy->get( zapp_runs => $run->{run_id} );
            is_deeply
                {
                    %$run,
                    input => decode_json( $run->{input} ),
                },
                {
                    $run->%{qw( run_id created started )},
                    $plan->%{qw( plan_id name description )},
                    input => {
                        destination => {
                            type => 'string',
                            value => 'Nude Beach Planet',
                        },
                        unused_value => {
                            type => 'string',
                            value => 'Should be passed through',
                        },
                    },
                    finished => undef,
                    state => 'active',
                },
                'database run is correct';

            my @got_tasks = $t->app->list_tasks( $run->{run_id}, { order_by => 'task_id' } );
            is_deeply
                $got_tasks[0],
                {
                    $got_tasks[0]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[0]{task_id},
                    $plan->{tasks}[0]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[0]{input} ),
                    run_id => $run->{run_id},
                    state => 'finished',
                    output => {
                        pid => $got_tasks[0]{output}{pid},
                        exit => 0,
                        output => "Nude Beach Planet\n",
                        error_output => "",
                        info => "Script exited with value: 0",
                    },
                },
                'first job run entry is correct';
            is_deeply
                $got_tasks[1],
                {
                    $got_tasks[1]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[1]{task_id},
                    $plan->{tasks}[1]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[1]{input} ),
                    run_id => $run->{run_id},
                    state => 'inactive',
                    output => undef,
                },
                'second job run entry is correct';
        };

        subtest 'run second job' => sub {
            my $worker = $t->app->minion->worker->register;
            my $job = $worker->dequeue;
            my $e = $job->execute;
            ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;
            is_deeply $job->args,
                [
                    {
                        vars => [
                            { name => 'dest', value => 'Nude Beach Planet' },
                        ],
                        script => 'echo Certain Doom on $dest',
                    },
                ],
                'minion job args are interpolated input';

            $run = $t->app->yancy->get( zapp_runs => $run->{run_id} );
            is_deeply
                {
                    %$run,
                    input => decode_json( $run->{input} ),
                },
                {
                    $run->%{qw( run_id created started finished )},
                    $plan->%{qw( plan_id name description )},
                    input => {
                        destination => {
                            type => 'string',
                            value => 'Nude Beach Planet',
                        },
                        unused_value => {
                            type => 'string',
                            value => 'Should be passed through',
                        },
                    },
                    state => 'finished',
                },
                'database run is correct';

            my @got_tasks = $t->app->list_tasks( $run->{run_id}, { order_by => 'task_id' } );
            is_deeply
                $got_tasks[0],
                {
                    $got_tasks[0]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[0]{task_id},
                    $plan->{tasks}[0]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[0]{input} ),
                    run_id => $run->{run_id},
                    state => 'finished',
                    output => {
                        pid => $got_tasks[0]{output}{pid},
                        exit => 0,
                        output => "Nude Beach Planet\n",
                        error_output => "",
                        info => "Script exited with value: 0",
                    },
                },
                'first job run entry is correct';
            is_deeply
                $got_tasks[1],
                {
                    $got_tasks[1]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[1]{task_id},
                    $plan->{tasks}[1]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[1]{input} ),
                    run_id => $run->{run_id},
                    state => 'finished',
                    output => {
                        pid => $got_tasks[1]{output}{pid},
                        exit => 0,
                        output => "Certain Doom on Nude Beach Planet\n",
                        error_output => "",
                        info => "Script exited with value: 0",
                    },
                },
                'second job run entry is correct';
        };
    };
};

done_testing;

