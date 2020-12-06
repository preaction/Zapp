
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
                class => 'Zapp::Task::Echo',
                args => encode_json({
                    destination => '{destination}',
                }),
                tests => [
                    {
                        expr => 'destination',
                        op => '!=',
                        value => '',
                    },
                ],
            },
            {
                name => 'Deliver package',
                class => 'Zapp::Task::Echo',
                args => encode_json({
                    destination => '{destination}',
                    delivery_address => 'Certain Doom on {destination}',
                }),
                tests => [
                    {
                        expr => 'destination',
                        op => '!=',
                        value => '',
                    },
                    {
                        expr => 'delivery_address',
                        op => '!=',
                        value => '',
                    },
                ],
            },
        ],
        inputs => [
            {
                name => 'destination',
                type => 'string',
                description => 'Where to send the crew to their doom',
                default_value => encode_json( 'Chapek 9' ),
            },
        ],
    });

    subtest 'tests pass' => sub {
        my $input = {
            destination => 'Nude Beach Planet',
        };

        my $run = $t->app->enqueue( $plan->{plan_id}, $input );

        # Check job results
        my $worker = $t->app->minion->worker->register;
        my $job = $worker->dequeue;
        my $e = $job->execute;
        ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;
        is_deeply $job->args,
            [
                {
                    destination => 'Nude Beach Planet',
                },
            ],
            'job args are interpolated with input';

        $job = $worker->dequeue;
        $e = $job->execute;
        ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;
        is_deeply $job->args,
            [
                {
                    destination => 'Nude Beach Planet',
                    delivery_address => 'Certain Doom on Nude Beach Planet',
                },
            ],
            'job args are interpolated with input';

        # Check test results
        my @tests = $t->app->yancy->list( zapp_run_tests => { run_id => $run->{run_id} }, { order_by => 'test_id' } );
        is scalar @tests, 3, '3 tests found for run';
        is_deeply $tests[0],
            {
                run_id => $run->{run_id},
                task_id => $plan->{tasks}[0]{task_id},
                test_id => $plan->{tasks}[0]{tests}[0]{test_id},
                expr => 'destination',
                op => '!=',
                value => '',
                expr_value => 'Nude Beach Planet',
                pass => 1,
            },
            'task 1 test 1 result correct'
                or diag explain $tests[0];
        is_deeply $tests[1],
            {
                run_id => $run->{run_id},
                task_id => $plan->{tasks}[1]{task_id},
                test_id => $plan->{tasks}[1]{tests}[0]{test_id},
                expr => 'destination',
                op => '!=',
                value => '',
                expr_value => 'Nude Beach Planet',
                pass => 1,
            },
            'task 2 test 1 result correct'
                or diag explain $tests[1];
        is_deeply $tests[2],
            {
                run_id => $run->{run_id},
                task_id => $plan->{tasks}[1]{task_id},
                test_id => $plan->{tasks}[1]{tests}[1]{test_id},
                expr => 'delivery_address',
                op => '!=',
                value => '',
                expr_value => 'Certain Doom on Nude Beach Planet',
                pass => 1,
            },
            'task 2 test 2 result correct'
                or diag explain $tests[2];
    };

    subtest 'tests fail' => sub {
        my $input = {
            destination => '',
        };

        my $run = $t->app->enqueue( $plan->{plan_id}, $input );

        # Check job results
        my $worker = $t->app->minion->worker->register;
        my $job = $worker->dequeue;
        my $e = $job->execute;
        ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;
        is $job->info->{state}, 'failed', 'job failed';

        # Check test results
        my @tests = $t->app->yancy->list( zapp_run_tests => { run_id => $run->{run_id} }, { order_by => 'test_id' } );
        is scalar @tests, 3, '3 tests found for run';
        is_deeply $tests[0],
            {
                run_id => $run->{run_id},
                task_id => $plan->{tasks}[0]{task_id},
                test_id => $plan->{tasks}[0]{tests}[0]{test_id},
                expr => 'destination',
                op => '!=',
                value => '',
                expr_value => '',
                pass => 0,
            },
            'task 1 test 1 result correct'
                or diag explain $tests[0];
        is_deeply $tests[1],
            {
                run_id => $run->{run_id},
                task_id => $plan->{tasks}[1]{task_id},
                test_id => $plan->{tasks}[1]{tests}[0]{test_id},
                expr => 'destination',
                op => '!=',
                value => '',
                expr_value => undef,
                pass => undef,
            },
            'task 2 test 1 result correct'
                or diag explain $tests[1];
        is_deeply $tests[2],
            {
                run_id => $run->{run_id},
                task_id => $plan->{tasks}[1]{task_id},
                test_id => $plan->{tasks}[1]{tests}[1]{test_id},
                expr => 'delivery_address',
                op => '!=',
                value => '',
                expr_value => undef,
                pass => undef,
            },
            'task 2 test 2 result correct'
                or diag explain $tests[2];
    };
};

done_testing;

