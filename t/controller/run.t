
=head1 DESCRIPTION

This tests Zapp::Controller::Plan (except for the JavaScript involved).

=cut

use Mojo::Base -strict, -signatures;
use Test::Zapp;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json );

my $mysqld = Test::mysqld->new(
    my_cnf => {
        sql_mode => 'ANSI,TRADITIONAL',
        # Needed for Minion::Backend::mysql
        log_bin_trust_function_creators => 1,
    },
) or plan skip_all => $Test::mysqld::errstr;

my $t = Test::Zapp->new( 'Zapp', {
    backend => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
    minion => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
} );

my $dump_debug = sub( $t ) {
    diag $t->tx->res->dom->find(
        '#error,#context,#insight,#trace,#log',
    )->map('to_string')->each;
};

subtest 'run a plan' => sub {
    $t->Test::Yancy::clear_backend;
    my $plan = $t->app->create_plan({
        name => 'Deliver a package',
        description => 'To a dangerous place',
        tasks => [
            {
                name => 'Plan trip',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo Chapek 9',
                }),
                tests => [
                    {
                        expr => 'output',
                        op => '!=',
                        value => '',
                    },
                ],
            },
            {
                name => 'Deliver package',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo Certain Doom',
                }),
                tests => [
                    {
                        expr => 'output',
                        op => '!=',
                        value => '',
                    },
                    {
                        expr => 'exit',
                        op => '==',
                        value => '0',
                    },
                ],
            },
        ],
        inputs => [
            {
                name => 'destination',
                type => 'string',
                description => 'Where to send the crew to their doom',
                config => encode_json( 'Chapek 9' ),
            },
        ],
    });
    my $plan_id = $plan->{plan_id};

    subtest 'create run form' => sub {
        $t->get_ok( "/plan/$plan_id/run" )->status_is( 200 )
            ->element_exists( "form[action=/plan/$plan_id/run]", 'form exists' )
            ->attr_is( "form[action=/plan/$plan_id/run]", enctype => 'multipart/form-data', 'form allows uploads' )
            ->text_is( '[data-input=0] [data-input-name]', 'destination', 'input label correct' )
            ->element_exists( '[name="input[0].value"]', 'input field exists' )
            ->attr_is( '[name="input[0].value"]', value => 'Chapek 9', 'input default value is correct' )
            ->element_exists( '[name="input[0].name"]', 'input name exists' )
            ->attr_is( '[name="input[0].name"]', value => 'destination', 'input name is correct' )
            ->element_exists( '[name="input[0].type"]', 'input type exists' )
            ->attr_is( '[name="input[0].type"]', value => 'string', 'input type is correct' )
            ;
    };

    subtest 'create a new run' => sub {
        $t->post_ok(
            "/plan/$plan_id/run",
            form => {
                'input[0].name' => 'destination',
                'input[0].type' => 'string',
                'input[0].value' => 'Galaxy of Terror',
            } )
            ->status_is( 302 )->or( $dump_debug )
            ->header_like( Location => qr{/run/\d+} )
            ;
        my ( $run_id ) = $t->tx->res->headers->location =~ m{/run/(\d+)};

        # Recorded in Zapp
        my $run = $t->app->yancy->get( zapp_runs => $run_id );
        is $run->{plan_id}, $plan_id, 'run plan_id is correct';
        is_deeply decode_json( $run->{input} ),
            {
                destination => {
                    type => 'string',
                    value => 'Galaxy of Terror',
                    config => 'Chapek 9',
                },
            },
            'run input is correct';

        # Record all enqueued tasks so we can keep track of which Minion
        # tasks were triggered by which Zapp run
        my @tasks = $t->app->yancy->list(
            zapp_run_tasks => { run_id => $run_id },
            { order_by => { -asc => 'job_id' } },
        );
        is scalar @tasks, 2, 'two run tasks created';
        is_deeply
            {
                $tasks[0]->%*,
                context => decode_json( $tasks[0]{context} ),
                input => decode_json( $tasks[0]{input} ),
            },
            {
                $tasks[0]->%{qw( job_id task_id )},
                $plan->{tasks}[0]->%{qw( name description class output )},
                input => decode_json( $plan->{tasks}[0]{input} ),
                context => {
                    destination => {
                        type => 'string',
                        value => 'Galaxy of Terror',
                        config => 'Chapek 9',
                    },
                },
                run_id => $run_id,
                plan_task_id => $plan->{tasks}[0]{task_id},
                state => 'inactive',
            },
            'first job is correct'
                or diag explain $tasks[0];
        is_deeply
            {
                $tasks[1]->%*,
                context => decode_json( $tasks[1]{context} ),
                input => decode_json( $tasks[1]{input} ),
            },
            {
                $tasks[1]->%{qw( job_id task_id )},
                $plan->{tasks}[1]->%{qw( name description class output )},
                input => decode_json( $plan->{tasks}[1]{input} ),
                context => {},
                run_id => $run_id,
                plan_task_id => $plan->{tasks}[1]{task_id},
                state => 'inactive',
            },
            'second job is correct'
                or diag explain $tasks[1];

        # Tests are copied to allow modifying job
        my @tests = $t->app->yancy->list(
            zapp_run_tests => { run_id => $run_id },
            { order_by => [ 'task_id', 'test_id' ] },
        );
        is scalar @tests, 3, 'three run tests created';
        is_deeply $tests[0],
            {
                run_id => $run_id,
                task_id => $tasks[0]{task_id},
                test_id => $tests[0]{test_id},
                expr => 'output',
                op => '!=',
                value => '',
                pass => undef,
                expr_value => undef,
            },
            'run task 1 test 1 is correct';
        is_deeply $tests[1],
            {
                run_id => $run_id,
                task_id => $tasks[1]{task_id},
                test_id => $tests[1]{test_id},
                expr => 'output',
                op => '!=',
                value => '',
                pass => undef,
                expr_value => undef,
            },
            'run task 2 test 1 is correct';
        is_deeply $tests[2],
            {
                run_id => $run_id,
                task_id => $tasks[1]{task_id},
                test_id => $tests[2]{test_id},
                expr => 'exit',
                op => '==',
                value => '0',
                pass => undef,
                expr_value => undef,
            },
            'run task 2 test 2 is correct';

        # Enqueued in Minion
        my $mjob = $t->app->minion->job( $tasks[0]{job_id} );
        ok $mjob, 'minion job 1 exists';
        # XXX: Test job attributes

        $mjob = $t->app->minion->job( $tasks[1]{job_id} );
        ok $mjob, 'minion job 2 exists';
        # XXX: Test job attributes
    };

};

subtest 'view run status' => sub {
    my $plan = $t->app->create_plan({
        name => 'Watch the What If Machine',
        tasks => [
            {
                name => 'Watch',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo {{Character}}',
                }),
            },
            {
                name => 'Experience Ironic Consequences',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo {{Character}}',
                }),
            },
        ],
        inputs => [
            {
                name => 'Character',
                type => 'string',
                description => 'Which character should ask the question?',
                config => encode_json( 'Leela' ),
            },
        ],
    });
    my $plan_id = $plan->{plan_id};
    my $run = $t->app->enqueue(
        $plan_id,
        {
            Character => {
                type => 'string',
                value => 'Zanthor',
            },
        },
    );

    subtest 'before execution' => sub {
        $t->get_ok( '/run/' . $run->{run_id} )->status_is( 200 )
            ->element_exists( '[href=/]', 'link back to plans exists' )
            ->text_is( '[data-run-state]', 'inactive', 'run state is correct' )
            ->text_is( '[data-run-started]', 'N/A', 'run started is correct' )
            ->text_is( '[data-run-finished]', 'N/A', 'run finished is correct' )
            ->text_is( "[data-task=$run->{tasks}[0]{task_id}] [data-task-state]", 'inactive', 'first task state is correct' )
            ->or( sub { diag $t->tx->res->dom( "[data-task=$run->{tasks}[0]{task_id}]" ) } )
            ->text_like( "[data-task=$run->{tasks}[0]{task_id}] code", qr/Zanthor/, 'first task input are interpolated' )
            ->text_is( "[data-task=$run->{tasks}[1]{task_id}] [data-task-state]", 'inactive', 'second task state is correct' )
            ->or( sub { diag $t->tx->res->dom( "[data-task=$run->{tasks}[1]{task_id}]" ) } )
            ->text_like( "[data-task=$run->{tasks}[1]{task_id}] code", qr/\{\{Character\}\}/, 'second task input are not yet interpolated' )
            ;

        $t->get_ok( '/run/' . $run->{run_id} . '/task/' . $run->{tasks}[0]{task_id} )
            ->status_is( 200 )
            ->element_exists_not( 'body', 'not inside layout' )
            ->text_like( "code", qr/Zanthor/, 'first task input are interpolated' )
            ;

        $t->get_ok( '/run/' . $run->{run_id} . '/task/' . $run->{tasks}[1]{task_id} )
            ->status_is( 200 )
            ->element_exists_not( 'body', 'not inside layout' )
            ->text_like( "code", qr/\{\{Character\}\}/, 'second task input are not interpolated' )
            ;
    };

    $t->run_queue;

    subtest 'after execution' => sub {
        $t->get_ok( '/run/' . $run->{run_id} )->status_is( 200 )
            ->element_exists( '[href=/]', 'link back to plans exists' )
            ->text_is( '[data-run-state]', 'finished', 'run state is correct' )
            ->text_like( '[data-run-started]', qr{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}}, 'run started is formatted correctly' )
            ->text_like( '[data-run-finished]',  qr{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}}, 'run finished is formatted correctly' )
            ->text_is( "[data-task=$run->{tasks}[0]{task_id}] [data-task-state]", 'finished', 'first task state is correct' )
            ->text_like( "[data-task=$run->{tasks}[0]{task_id}] code", qr/Zanthor/, 'first task input are interpolated' )
            ->text_is( "[data-task=$run->{tasks}[1]{task_id}] [data-task-state]", 'finished', 'second task state is correct' )
            ->text_like( "[data-task=$run->{tasks}[1]{task_id}] code", qr/Zanthor/, 'second task input are interpolated' )
            ;

        $t->get_ok( '/run/' . $run->{run_id} . '/task/' . $run->{tasks}[0]{task_id} )
            ->status_is( 200 )
            ->element_exists_not( 'body', 'not inside layout' )
            ->text_like( "code", qr/Zanthor/, 'first task input are interpolated' )
            ;

        $t->get_ok( '/run/' . $run->{run_id} . '/task/' . $run->{tasks}[1]{task_id} )
            ->status_is( 200 )
            ->element_exists_not( 'body', 'not inside layout' )
            ->text_like( "code", qr/Zanthor/, 'second task input are interpolated' )
            ;
    };
};

subtest 'stop/kill run' => sub {
    my $plan = $t->app->create_plan({
        name => 'Open the Scary Door',
        tasks => [
            {
                name => 'Open',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo The door creaks spookily',
                }),
            },
            {
                name => 'Twist Ending',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo Saw it coming',
                }),
            },
        ],
    });
    my $plan_id = $plan->{plan_id};

    subtest 'stop run' => sub {
        my $run = $t->app->enqueue( $plan_id, {} );

        # Run view screen shows start/stop buttons
        $t->get_ok( "/run/$run->{run_id}" )->status_is( 200 )
            ->element_exists( "[href=/run/$run->{run_id}/stop]", 'stop link exists' )
            ->element_exists_not( "[href=/run/$run->{run_id}/stop].disabled", 'stop link not disabled' )
            ->element_exists( qq{form[action="/run/$run->{run_id}/start"]}, 'start form exists' )
            ->element_exists( qq{form[action="/run/$run->{run_id}/start"] button[disabled]}, 'start form button disabled exists' )
            ->element_exists( "[href=/run/$run->{run_id}/kill]", 'kill link exists' )
            ->element_exists_not( "[href=/run/$run->{run_id}/kill].disabled", 'kill link not disabled' )
            ;

        # Do one job before stopping
        my $worker = $t->app->minion->worker->register;
        my $job = $worker->dequeue;
        my $e = $job->execute;
        $worker->unregister;

        # Show stop run form
        $t->get_ok( "/run/$run->{run_id}/stop" )->status_is( 200 )
            ->element_exists( 'form' )
            ->attr_is( 'form', action => "/run/$run->{run_id}/stop" )
            ->attr_like( 'form', method => qr{post}i )
            ->element_exists( 'textarea' )
            ->attr_is( 'textarea', name => 'note' )
            ->element_exists( 'button' )
            ;

        # Stop the run
        $t->post_ok( "/run/$run->{run_id}/stop",
                form => {
                    note => 'You only stamped it four times!',
                },
            )
            ->status_is( 302 )
            ->header_is( Location => "/run/$run->{run_id}" )
            ;

        # Run note is added
        my @notes = $t->app->yancy->list( zapp_run_notes => { $run->%{'run_id'} } );
        is scalar @notes, 1, 'one note found';
        like $notes[0]{created}, qr{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}};
        is $notes[0]{event}, 'stop';
        is $notes[0]{note}, 'You only stamped it four times!';

        # Run state "stopped"
        my $set_run = $t->app->yancy->get( zapp_runs => $run->{run_id} );
        is $set_run->{state}, 'stopped', 'run state is correct';

        # Zapp job state "stopped"
        my $task = $t->app->yancy->get( zapp_run_tasks => $run->{tasks}[1]{task_id} );
        is $task->{state}, 'stopped', 'zapp job state is correct'
            or diag explain [ $run->{tasks}[1], $task ];

        # Minion job removed
        ok !$t->app->minion->job( $run->{task}[1]{job_id} ), 'minion job removed';

        # Job cannot be dequeued
        $worker = $t->app->minion->worker->register;
        ok !$worker->dequeue(0), 'no job to dequeue';
        $worker->unregister;

        # Job view screen shows Start button
        $t->get_ok( "/run/$run->{run_id}" )->status_is( 200 )
            ->element_exists( "[href=/run/$run->{run_id}/stop]", 'stop link exists' )
            ->element_exists( "[href=/run/$run->{run_id}/stop].disabled", 'stop link is disabled' )
            ->element_exists( "form[action=/run/$run->{run_id}/start]", 'start form exists' )
            ->element_exists_not( "form[action=/run/$run->{run_id}/start] button[disabled]", 'start form button not disabled' )
            ->element_exists( "[href=/run/$run->{run_id}/kill]", 'kill link exists' )
            ->element_exists_not( "[href=/run/$run->{run_id}/kill].disabled", 'kill link not disabled' )
            ;

        # Start the run
        $t->post_ok( "/run/$run->{run_id}/start" )->status_is( 302 )
            ->header_is( Location => "/run/$run->{run_id}" )
            ;

        # Zapp job state "inactive"
        $task = $t->app->yancy->get( zapp_run_tasks => $run->{tasks}[1]{task_id} );
        is $task->{state}, 'inactive', 'zapp run task state is correct';

        # Minion job state "inactive"
        $job = $t->app->minion->job( $task->{job_id} );
        is $job->info->{state}, 'inactive', 'minion job state is correct';

        # Job can be dequeued
        $worker = $t->app->minion->worker->register;
        $job = $worker->dequeue(0);
        ok $job, 'job dequeued';
        $job->execute;
        $worker->unregister;

        # Run screen shows stop/start buttons both disabled
        $t->get_ok( "/run/$run->{run_id}" )->status_is( 200 )
            ->element_exists( "[href=/run/$run->{run_id}/stop]", 'stop link exists' )
            ->element_exists( "[href=/run/$run->{run_id}/stop].disabled", 'stop link disabled' )
            ->element_exists( "form[action=/run/$run->{run_id}/start]", 'start form exists' )
            ->element_exists( "form[action=/run/$run->{run_id}/start] button[disabled]", 'start form button disabled' )
            ->element_exists( "[href=/run/$run->{run_id}/kill]", 'kill link exists' )
            ->element_exists( "[href=/run/$run->{run_id}/kill].disabled", 'kill link disabled' )
            ;
    };

    subtest 'kill run' => sub {
        my @signals;
        local $SIG{TERM} = sub { push @signals, 'TERM' };

        my $run = $t->app->enqueue( $plan_id );

        # Run view screen shows kill button
        $t->get_ok( "/run/$run->{run_id}" )->status_is( 200 )
            ->element_exists( "[href=/run/$run->{run_id}/stop]", 'stop link exists' )
            ->element_exists_not( "[href=/run/$run->{run_id}/stop].disabled", 'stop link not disabled' )
            ->element_exists( "form[action=/run/$run->{run_id}/start]", 'start form exists' )
            ->element_exists( "form[action=/run/$run->{run_id}/start] button[disabled]", 'start form button disabled' )
            ->element_exists( "[href=/run/$run->{run_id}/kill]", 'kill link exists' )
            ->element_exists_not( "[href=/run/$run->{run_id}/kill].disabled", 'kill link not disabled' )
            ;

        # Do one job before killing
        my $worker = $t->app->minion->worker->register;
        my $job = $worker->dequeue;
        my $e = $job->execute;
        $worker->unregister;

        # Show kill run form
        $t->get_ok( "/run/$run->{run_id}/kill" )->status_is( 200 )
            ->element_exists( 'form' )
            ->attr_is( 'form', action => "/run/$run->{run_id}/kill" )
            ->attr_like( 'form', method => qr{post}i )
            ->element_exists( 'textarea' )
            ->attr_is( 'textarea', name => 'note' )
            ->element_exists( 'button' )
            ;

        # Kill the run
        $t->post_ok( "/run/$run->{run_id}/kill",
                form => {
                    note => 'I was young, and reckless!',
                },
            )
            ->status_is( 302 )
            ->header_is( Location => "/run/$run->{run_id}" )
            ;

        # Run note is added
        my @notes = $t->app->yancy->list( zapp_run_notes => { $run->%{'run_id'} } );
        is scalar @notes, 1, 'one note found';
        like $notes[0]{created}, qr{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}};
        is $notes[0]{event}, 'kill';
        is $notes[0]{note}, 'I was young, and reckless!';

        # Run state "killed"
        my $set_run = $t->app->yancy->get( zapp_runs => $run->{run_id} );
        is $set_run->{state}, 'killed', 'run state is correct';
        like $set_run->{finished}, qr{\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}}, 'run finished is set';

        # Zapp job state "killed"
        my $task = $t->app->yancy->get( zapp_run_tasks => $run->{tasks}[1]{task_id} );
        is $task->{state}, 'killed', 'zapp run task state is correct';
        ok !$task->{finished}, 'task finished is not set';

        # Minion job removed
        ok !$t->app->minion->job( $task->{job_id} ), 'minion job removed';

        # Job cannot be started again
        $worker = $t->app->minion->worker->register;
        $job = $worker->dequeue(0);
        $worker->unregister;
        ok !$job, 'no job dequeued' or diag explain $job->info;

        # Job view screen shows disabled buttons
        $t->get_ok( "/run/$run->{run_id}" )->status_is( 200 )
            ->element_exists( "[href=/run/$run->{run_id}/stop]", 'stop link exists' )
            ->element_exists( "[href=/run/$run->{run_id}/stop].disabled", 'stop link disabled' )
            ->element_exists( "form[action=/run/$run->{run_id}/start]", 'start form exists' )
            ->element_exists( "form[action=/run/$run->{run_id}/start] button[disabled]", 'start form button disabled' )
            ->element_exists( "[href=/run/$run->{run_id}/kill]", 'kill link exists' )
            ->element_exists( "[href=/run/$run->{run_id}/kill].disabled", 'kill link disabled' )
            ;

    };
};

done_testing;

sub Test::Yancy::clear_backend {
    my ( $self ) = @_;
    my %tables = (
        zapp_plans => 'plan_id',
        zapp_plan_inputs => [ 'plan_id', 'name' ],
        zapp_plan_tasks => 'task_id',
        zapp_plan_task_parents => 'task_id',
    );
    for my $table ( keys %tables ) {
        my $id_field = $tables{ $table };
        for my $item ( $self->app->yancy->list( $table ) ) {
            my $id = ref $id_field eq 'ARRAY'
                ? { map { $_ => $item->{ $_ } } @$id_field }
                : $item->{ $id_field }
                ;
            $self->app->yancy->backend->delete( $table => $id );
        }
    }
}
