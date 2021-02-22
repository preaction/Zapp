
=head1 DESCRIPTION

This tests the base Zapp::Task class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Mojo;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json );

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

subtest 'execute' => sub {
    my $plan = $t->app->create_plan({
        name => 'Deliver a package',
        description => 'To a dangerous place',
        tasks => [
            {
                name => 'Plan trip',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo {{destination}}',
                }),
                tests => [
                    {
                        expr => 'output',
                        op => '!=',
                        value => "\n",
                    },
                ],
                output => encode_json([
                    { name => 'initial_destination', type => 'string', expr => 'output' },
                ]),
            },
            {
                name => 'Deliver package',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo Certain Doom on {{destination}}',
                }),
                tests => [
                    {
                        expr => 'output',
                        op => '!=',
                        value => "\n",
                    },
                    {
                        expr => 'exit',
                        op => '==',
                        value => '0',
                    },
                ],
                output => encode_json([
                    { name => 'final_destination', type => 'string', expr => 'output' },
                    { name => 'deaths', type => 'integer', expr => 'exit' },
                ]),
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

    subtest 'tests pass' => sub {
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
                output => undef,
            },
            'database run is correct';

        # Check jobs created correctly
        my @got_tasks = $t->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} }, { order_by => 'task_id' } );
        is_deeply
            {
                $got_tasks[0]->%*,
                context => decode_json( $got_tasks[0]{context} ),
                input => decode_json( $got_tasks[0]{input} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                $got_tasks[0]->%{qw( job_id task_id )},
                input => decode_json( $plan->{tasks}[0]{input} ),
                output => decode_json( $plan->{tasks}[0]{output} ),
                plan_task_id => $plan->{tasks}[0]{task_id},
                $plan->{tasks}[0]->%{qw( name description class )},
                run_id => $run->{run_id},
                context => {
                    destination => {
                        type => 'string',
                        value => 'Nude Beach Planet',
                    },
                    unused_value => {
                        type => 'string',
                        value => 'Should be passed through',
                    },
                },
                state => 'inactive',
            },
            'first job run entry is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                context => decode_json( $got_tasks[1]{context} ),
                input => decode_json( $got_tasks[1]{input} ),
                output => decode_json( $got_tasks[1]{output} ),
            },
            {
                $got_tasks[1]->%{qw( job_id task_id )},
                plan_task_id => $plan->{tasks}[1]{task_id},
                $plan->{tasks}[1]->%{qw( name description class )},
                input => decode_json( $plan->{tasks}[1]{input} ),
                output => decode_json( $plan->{tasks}[1]{output} ),
                run_id => $run->{run_id},
                context => {},
                state => 'inactive',
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
                        script => 'echo Nude Beach Planet',
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
                    output => undef,
                },
                'database run is correct';

            my @got_tasks = $t->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} }, { order_by => 'task_id' } );
            is_deeply
                {
                    $got_tasks[0]->%*,
                    context => decode_json( $got_tasks[0]{context} ),
                    input => decode_json( $got_tasks[0]{input} ),
                    output => decode_json( $got_tasks[0]{output} ),
                },
                {
                    $got_tasks[0]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[0]{task_id},
                    $plan->{tasks}[0]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[0]{input} ),
                    output => decode_json( $plan->{tasks}[0]{output} ),
                    run_id => $run->{run_id},
                    context => {
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
                'first job run entry is correct';
            is_deeply
                {
                    $got_tasks[1]->%*,
                    context => decode_json( $got_tasks[1]{context} ),
                    input => decode_json( $got_tasks[1]{input} ),
                    output => decode_json( $got_tasks[1]{output} ),
                },
                {
                    $got_tasks[1]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[1]{task_id},
                    $plan->{tasks}[1]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[1]{input} ),
                    output => decode_json( $plan->{tasks}[1]{output} ),
                    run_id => $run->{run_id},
                    context => {
                        destination => {
                            type => 'string',
                            value => 'Nude Beach Planet',
                        },
                        unused_value => {
                            type => 'string',
                            value => 'Should be passed through',
                        },
                        initial_destination => {
                            type => 'string',
                            value => "Nude Beach Planet\n",
                            config => undef,
                        },
                    },
                    state => 'inactive',
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
                        script => 'echo Certain Doom on Nude Beach Planet',
                    },
                ],
                'minion job args are interpolated input';

            $run = $t->app->yancy->get( zapp_runs => $run->{run_id} );
            is_deeply
                {
                    %$run,
                    input => decode_json( $run->{input} ),
                    output => decode_json( $run->{output} ),
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
                    output => {
                        initial_destination => {
                            type => 'string',
                            value => "Nude Beach Planet\n",
                            config => undef,
                        },
                        destination => {
                            type => 'string',
                            value => 'Nude Beach Planet',
                        },
                        final_destination => {
                            type => 'string',
                            value => "Certain Doom on Nude Beach Planet\n",
                            config => undef,
                        },
                        unused_value => {
                            type => 'string',
                            value => 'Should be passed through',
                        },
                        deaths => {
                            type => 'integer',
                            value => 0,
                            config => undef,
                        },
                    },
                },
                'database run is correct';

            my @got_tasks = $t->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} }, { order_by => 'task_id' } );
            is_deeply
                {
                    $got_tasks[0]->%*,
                    context => decode_json( $got_tasks[0]{context} ),
                    input => decode_json( $got_tasks[0]{input} ),
                    output => decode_json( $got_tasks[0]{output} ),
                },
                {
                    $got_tasks[0]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[0]{task_id},
                    $plan->{tasks}[0]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[0]{input} ),
                    output => decode_json( $plan->{tasks}[0]{output} ),
                    run_id => $run->{run_id},
                    context => {
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
                'first job run entry is correct';
            is_deeply
                {
                    $got_tasks[1]->%*,
                    context => decode_json( $got_tasks[1]{context} ),
                    input => decode_json( $got_tasks[1]{input} ),
                    output => decode_json( $got_tasks[1]{output} ),
                },
                {
                    $got_tasks[1]->%{qw( job_id task_id )},
                    plan_task_id => $plan->{tasks}[1]{task_id},
                    $plan->{tasks}[1]->%{qw( name description class )},
                    input => decode_json( $plan->{tasks}[1]{input} ),
                    output => decode_json( $plan->{tasks}[1]{output} ),
                    run_id => $run->{run_id},
                    context => {
                        destination => {
                            type => 'string',
                            value => 'Nude Beach Planet',
                        },
                        unused_value => {
                            type => 'string',
                            value => 'Should be passed through',
                        },
                        initial_destination => {
                            type => 'string',
                            value => "Nude Beach Planet\n",
                            config => undef,
                        },
                    },
                    state => 'finished',
                },
                'second job run entry is correct';
        };

        # Check test results
        my @tests = $t->app->yancy->list( zapp_run_tests => { run_id => $run->{run_id} }, { order_by => 'test_id' } );
        is scalar @tests, 3, '3 tests found for run';
        is_deeply $tests[0],
            {
                test_id => $tests[0]{test_id},
                run_id => $run->{run_id},
                task_id => $tasks[0]{task_id},
                expr => 'output',
                op => '!=',
                value => "\n",
                expr_value => "Nude Beach Planet\n",
                pass => 1,
            },
            'task 1 test 1 result correct'
                or diag explain $tests[0];
        is_deeply $tests[1],
            {
                test_id => $tests[1]{test_id},
                run_id => $run->{run_id},
                task_id => $tasks[1]{task_id},
                expr => 'output',
                op => '!=',
                value => "\n",
                expr_value => "Certain Doom on Nude Beach Planet\n",
                pass => 1,
            },
            'task 2 test 1 result correct'
                or diag explain $tests[1];
        is_deeply $tests[2],
            {
                test_id => $tests[2]{test_id},
                run_id => $run->{run_id},
                task_id => $tasks[1]{task_id},
                expr => 'exit',
                op => '==',
                value => '0',
                expr_value => '0',
                pass => 1,
            },
            'task 2 test 2 result correct'
                or diag explain $tests[2];
    };

    subtest 'tests fail' => sub {
        my $input = {
            destination => {
                type => 'string',
                value => '',
            },
        };

        my $run = $t->app->enqueue( $plan->{plan_id}, $input );

        # Check job results
        my $worker = $t->app->minion->worker->register;
        my $job = $worker->dequeue;
        my $e = $job->execute;
        ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;
        is $job->info->{state}, 'failed', 'job failed';

        my @got_tasks = $t->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} }, { order_by => 'task_id' } );
        is_deeply
            {
                $got_tasks[0]->%*,
                context => decode_json( $got_tasks[0]{context} ),
                input => decode_json( $got_tasks[0]{input} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                $got_tasks[0]->%{qw( job_id task_id )},
                plan_task_id => $plan->{tasks}[0]{task_id},
                $plan->{tasks}[0]->%{qw( name description class )},
                input => decode_json( $plan->{tasks}[0]{input} ),
                output => decode_json( $plan->{tasks}[0]{output} ),
                run_id => $run->{run_id},
                context => {
                    destination => {
                        type => 'string',
                        value => '',
                    },
                },
                state => 'failed',
            },
            'first job run entry is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                context => decode_json( $got_tasks[1]{context} ),
                input => decode_json( $got_tasks[1]{input} ),
                output => decode_json( $got_tasks[1]{output} ),
            },
            {
                $got_tasks[1]->%{qw( job_id task_id )},
                plan_task_id => $plan->{tasks}[1]{task_id},
                $plan->{tasks}[1]->%{qw( name description class )},
                input => decode_json( $plan->{tasks}[1]{input} ),
                output => decode_json( $plan->{tasks}[1]{output} ),
                run_id => $run->{run_id},
                context => {},
                state => 'inactive',
            },
            'second job run entry is correct';

        # Check test results
        my @tests = $t->app->yancy->list( zapp_run_tests => { run_id => $run->{run_id} }, { order_by => 'test_id' } );
        is scalar @tests, 3, '3 tests found for run';
        is_deeply $tests[0],
            {
                test_id => $tests[0]{test_id},
                run_id => $run->{run_id},
                task_id => $run->{tasks}[0]{task_id},
                expr => 'output',
                op => '!=',
                value => "\n",
                expr_value => "\n",
                pass => 0,
            },
            'task 1 test 1 result correct'
                or diag explain $tests[0];
        is_deeply $tests[1],
            {
                test_id => $tests[1]{test_id},
                run_id => $run->{run_id},
                task_id => $run->{tasks}[1]{task_id},
                expr => 'output',
                op => '!=',
                value => "\n",
                expr_value => undef,
                pass => undef,
            },
            'task 2 test 1 result correct'
                or diag explain $tests[1];
        is_deeply $tests[2],
            {
                test_id => $tests[2]{test_id},
                run_id => $run->{run_id},
                task_id => $run->{tasks}[1]{task_id},
                expr => 'exit',
                op => '==',
                value => '0',
                expr_value => undef,
                pass => undef,
            },
            'task 2 test 2 result correct'
                or diag explain $tests[2];
    };
};

done_testing;

