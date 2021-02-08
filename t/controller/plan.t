
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

subtest 'create new plan' => sub {

    subtest 'new plan form' => sub {
        $t->get_ok( '/plan' )->status_is( 200 )
            ->or( $dump_debug )
            ->element_exists( 'form#plan', 'form exists' )
            ->attr_is( 'form#plan', enctype => 'multipart/form-data', 'form enctype correct' )
            ->element_exists(
                'label[for=name]',
                'name label exists',
            )
            ->element_exists(
                'input[id=name]',
                'name input exists',
            )
            ->attr_is(
                'input[id=name]',
                name => 'name',
                'name input name is correct',
            )
            ->element_exists(
                'label[for=description]',
                'description label exists',
            )
            ->element_exists(
                'textarea[id=description]',
                'description textarea exists',
            )
            ->attr_is(
                'textarea[id=description]',
                name => 'description',
                'description textarea name is correct',
            )
            ->element_exists(
                'select.add-input',
                'add input dropdown exists',
            )
            ->element_exists(
                'select.add-task',
                'add task dropdown exists',
            )
            ->text_is(
                'select.add-task option:nth-child(1)',
                'Add Task...',
                'placeholder for add task dropdown is correct',
            )
            ->element_exists(
                'select.add-task option[value=Zapp::Task::Request]',
                'Request task appears in task list',
            )
            ->text_is(
                'select.add-task option[value=Zapp::Task::Request]',
                'Request',
                'Request task option text is correct',
            )
            ->element_exists(
                'select.add-task option[value=Zapp::Task::Script]',
                'Script task appears in task list',
            )
            ->text_is(
                'select.add-task option[value=Zapp::Task::Script]',
                'Script',
                'Script task option text is correct',
            )
            ;

    };

    subtest 'save plan' => sub {
        $t->post_ok( "/plan",
            form => {
                name => 'The Mighty One',
                description => 'Save the mighty one, save the universe.',
                'input[0].name' => 'prank_name',
                'input[0].type' => 'string',
                'input[0].description' => 'A funny name to demoralize the Mighty One',
                'input[0].default_value' => 'I.C. Weiner',
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Order pizza',
                'task[0].description' => 'I.C. Weiner',
                'task[0].input.script' => 'make order',
                'task[0].tests[0].expr' => 'exit',
                'task[0].tests[0].op' => '==',
                'task[0].tests[0].value' => '0',
                'task[0].output[0].name' => 'last_exit',
                'task[0].output[0].expr' => 'exit',
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Verify',
                'task[1].description' => 'Verify freezer',
                'task[1].input.script' => 'make test',
                'task[1].tests[0].expr' => 'exit',
                'task[1].tests[0].op' => '!=',
                'task[1].tests[0].value' => '1',
                'task[1].output[0].name' => 'last_exit',
                'task[1].output[0].expr' => 'exit',
            },
        );
        $t->status_is( 302 )->or( sub( $t ) { diag $t->tx->res->dom->find( '#error,#context,#trace,#log' )->each } );
        $t->header_like( Location => qr{/plan/(\d+)} );
        my ( $plan_id ) = $t->tx->res->headers->location =~ m{/plan/(\d+)};

        my $got_plan = $t->app->yancy->get( zapp_plans => $plan_id );
        ok $got_plan, 'found plan';
        is $got_plan->{name}, 'The Mighty One', 'plan name correct';
        is $got_plan->{description}, 'Save the mighty one, save the universe.', 'plan description correct';

        my @got_tasks = $t->app->yancy->list(
            zapp_plan_tasks => {
                plan_id => $plan_id,
            },
            {
                order_by => 'task_id',
            },
        );
        is scalar @got_tasks, 2, 'got 2 tasks for plan';
        is_deeply
            {
                $got_tasks[0]->%*,
                input => decode_json( $got_tasks[0]{input} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                plan_id => $got_plan->{plan_id},
                task_id => $got_tasks[0]{task_id},
                class =>'Zapp::Task::Script',
                name => 'Order pizza',
                description => 'I.C. Weiner',
                input => {
                    script => 'make order',
                },
                output => [
                    { name => 'last_exit', expr => 'exit' },
                ],
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
                output => decode_json( $got_tasks[1]{output} ),
            },
            {
                plan_id => $got_plan->{plan_id},
                task_id => $got_tasks[1]{task_id},
                class =>'Zapp::Task::Script',
                name => 'Verify',
                description => 'Verify freezer',
                input => {
                    script => 'make test',
                },
                output => [
                    { name => 'last_exit', expr => 'exit' },
                ],
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_task_parents => {
            task_id => [ map { $_->{task_id} } @got_tasks ],
        });
        is scalar @got_parents, 1, 'got 1 relationship for plan';
        is_deeply $got_parents[0], {
            task_id => $got_tasks[1]{task_id},
            parent_task_id => $got_tasks[0]{task_id},
        };

        my @got_inputs = $t->app->yancy->list( zapp_plan_inputs =>
            {
                plan_id => $got_plan->{plan_id},
            },
            {
                order_by => 'name',
            },
        );
        is scalar @got_inputs, 1, 'got 1 inputs for plan';
        is_deeply $got_inputs[0], {
            plan_id => $plan_id,
            name => 'prank_name',
            type => 'string',
            description => 'A funny name to demoralize the Mighty One',
            default_value => encode_json( 'I.C. Weiner' ),
        };

        my @got_tests = $t->app->yancy->list(
            zapp_plan_tests => {
                plan_id => $plan_id,
            },
            {
                order_by => [ qw( test_id task_id ) ],
            },
        );
        is scalar @got_tests, 2, 'got 2 tests for plan';
        is_deeply $got_tests[0],
            {
                test_id => $got_tests[0]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[0]{task_id},
                expr => 'exit',
                op => '==',
                value => '0',
            },
            'test 1 is correct';
        is_deeply $got_tests[1],
            {
                test_id => $got_tests[1]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[1]{task_id},
                expr => 'exit',
                op => '!=',
                value => '1',
            },
            'test 2 is correct';

    };

};

subtest 'edit existing plan' => sub {

    my $plan = $t->app->create_plan( {
        name => 'Blow up Garbage Ball',
        description => 'Save New New York from certain, smelly doom.',
        tasks => [
            {
                name => 'Deploy the Bomb',
                description => 'Deploy the bomb between the Bart Simpson dolls.',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => "liftoff;\ndrop the_bomb\n",
                }),
                tests => [
                    {
                        expr => 'exit',
                        op => '==',
                        value => '0',
                    },
                ],
                output => encode_json([
                    { name => 'last_exit', expr => 'exit' },
                ]),
            },
            {
                name => 'Activate the Bomb',
                description => q{Let's blow it up already!},
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => "make explosion",
                }),
                tests => [
                    {
                        expr => 'bomb.timer',
                        op => '==',
                        value => '25:00',
                    },
                    {
                        expr => 'bomb.rotation',
                        op => '!=',
                        value => '180',
                    },
                ],
                output => encode_json([
                    { name => 'last_exit', expr => 'exit' },
                ]),
            },
        ],
        inputs => [
            {
                name => 'location',
                type => 'string',
                description => 'Where to place the bomb',
                default_value => encode_json( 'In the center' ),
            },
            {
                name => 'delay',
                type => 'number',
                description => 'Time to give crew to survive, in minutes',
                default_value => encode_json( 25 ),
            },
        ],
    } );
    my $plan_id = $plan->{plan_id};
    my @task_ids = map { $_->{task_id} } @{ $plan->{tasks} };

    subtest 'edit plan form' => sub {
        $t->get_ok( "/plan/$plan_id" )->status_is( 200 )
            ->or( $dump_debug )
            ->element_exists( 'form#plan', 'form exists' )
            ->element_exists(
                'label[for=name]',
                'name label exists',
            )
            ->element_exists(
                'input[id=name]',
                'name input exists',
            )
            ->attr_is(
                'input[id=name]',
                name => 'name',
                'name input name is correct',
            )
            ->attr_is(
                'input[id=name]',
                value => 'Blow up Garbage Ball',
                'name input value is correct',
            )
            ->element_exists(
                'label[for=description]',
                'description label exists',
            )
            ->element_exists(
                'textarea[id=description]',
                'description textarea exists',
            )
            ->attr_is(
                'textarea[id=description]',
                name => 'description',
                'description textarea name is correct',
            )
            ->text_is(
                'textarea[id=description]',
                'Save New New York from certain, smelly doom.',
                'description textarea value is correct',
            )
            ->element_exists(
                'select.add-input',
                'add input dropdown exists',
            )
            ->element_exists(
                'select.add-task',
                'add task dropdown exists',
            )
            ->text_is(
                'select.add-task option:nth-child(1)',
                'Add Task...',
                'placeholder for add task dropdown is correct',
            )
            ->element_exists(
                'select.add-task option[value=Zapp::Task::Request]',
                'Request task appears in task list',
            )
            ->text_is(
                'select.add-task option[value=Zapp::Task::Request]',
                'Request',
                'Request task option text is correct',
            )
            ->element_exists(
                'select.add-task option[value=Zapp::Task::Script]',
                'Script task appears in task list',
            )
            ->text_is(
                'select.add-task option[value=Zapp::Task::Script]',
                'Script',
                'Script task option text is correct',
            )
            ;

        subtest 'inputs form' => sub {
            $t->element_exists(
                'form [name="input[0].name"]',
                'first input name input exists',
            );
            $t->attr_is(
                'form [name="input[0].name"]',
                value => 'delay',
                'first input name input value is correct',
            ) or diag $t->tx->res->dom->at( 'form [name="input[0].name"]' );
            $t->element_exists(
                'form [name="input[0].type"]',
                'first input type input exists',
            );
            $t->attr_is(
                'form [name="input[0].type"]',
                value => 'number',
                'first input type input value is correct',
            );
            $t->element_exists(
                'form [name="input[0].description"]',
                'first input description input exists',
            );
            $t->text_is(
                'form [name="input[0].description"]',
                'Time to give crew to survive, in minutes',
                'first input description input value is correct',
            );
            $t->element_exists(
                'form [name="input[0].default_value"]',
                'first input default input exists',
            );
            $t->attr_is(
                'form [name="input[0].default_value"]',
                value => '25',
                'first input default value input value is correct',
            );

            $t->element_exists(
                'form [name="input[1].name"]',
                'second input name input exists',
            );
            $t->attr_is(
                'form [name="input[1].name"]',
                value => 'location',
                'second input name input value is correct',
            );
            $t->element_exists(
                'form [name="input[1].type"]',
                'second input type input exists',
            );
            $t->attr_is(
                'form [name="input[1].type"]',
                value => 'string',
                'second input type input value is correct',
            );
            $t->element_exists(
                'form [name="input[1].description"]',
                'second input description input exists',
            );
            $t->text_is(
                'form [name="input[1].description"]',
                'Where to place the bomb',
                'second input description input value is correct',
            );
            $t->element_exists(
                'form [name="input[1].default_value"]',
                'second input default input exists',
            );
            $t->attr_is(
                'form [name="input[1].default_value"]',
                value => 'In the center',
                'second input default value input value is correct',
            );

        };

        subtest 'task 0 form' => sub {
            $t->element_exists(
                'input[name="task[0].class"]',
                'first plan task class input exists',
            );
            $t->attr_is(
                'input[name="task[0].class"]',
                value => 'Zapp::Task::Script',
                'first plan task class input value correct',
            );

            $t->element_exists(
                'input[name="task[0].task_id"]',
                'first plan task id input exists',
            );
            $t->attr_is(
                'input[name="task[0].task_id"]',
                value => $task_ids[0],
                'first plan task id input value correct',
            );

            $t->element_exists(
                'input[name="task[0].name"]',
                'first plan task name input exists',
            );
            $t->attr_is(
                'input[name="task[0].name"]',
                value => 'Deploy the Bomb',
                'first plan task name input value correct',
            );

            $t->element_exists(
                'textarea[name="task[0].description"]',
                'first plan task description textarea exists',
            );
            $t->text_is(
                'textarea[name="task[0].description"]',
                'Deploy the bomb between the Bart Simpson dolls.',
                'first plan task description textarea value correct',
            );

            $t->element_exists(
                'textarea[name="task[0].input.script"]',
                'task script textarea exists',
            );
            $t->text_is(
                'textarea[name="task[0].input.script"]',
                "liftoff;\ndrop the_bomb\n",
                'first plan task description textarea value correct',
            );

            subtest 'tests' => sub {
                subtest 'test 1' => sub {
                    $t->element_exists(
                        'input[name="task[0].tests[0].test_id"]',
                        'task 1 test 1 test_id field exists',
                    )->or( sub {
                        diag join "\n", $t->tx->res->dom( '[name^="task[0].test"]' )->each;
                    } );
                    $t->attr_is(
                        'input[name="task[0].tests[0].test_id"]',
                        value => $plan->{tasks}[0]{tests}[0]{test_id},
                        'task 1 test 1 test_id value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[0].tests[0].expr"]',
                        'task 1 test 1 expr input exists',
                    );
                    $t->attr_is(
                        'input[name="task[0].tests[0].expr"]',
                        value => 'exit',
                        'task 1 test 1 expr value is correct',
                    );
                    $t->element_exists(
                        '[name="task[0].tests[0].op"]',
                        'task 1 test 1 op field exists',
                    );
                    $t->attr_is(
                        '[name="task[0].tests[0].op"] option[selected]',
                        value => '==',
                        'task 1 test 1 op value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[0].tests[0].value"]',
                        'task 1 test 1 value field exists',
                    );
                    $t->attr_is(
                        'input[name="task[0].tests[0].value"]',
                        value => '0',
                        'task 1 test 1 value value is correct',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(1) .tests > :nth-child(1) button.test-remove',
                        'task 1 test 1 remove button exists',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(1) .tests > :nth-child(1) button.test-remove',
                        'task 1 test 1 remove button exists',
                    );
                };
                $t->element_exists(
                    '#all-tasks > :nth-child(1) button.test-add',
                    'task 1 add test button exists',
                );
            };

            subtest 'output' => sub {
                subtest 'task 1' => sub {
                    $t->element_exists(
                        'input[name="task[0].output[0].name"]',
                        'task 1 output 1 name input exists',
                    );
                    $t->attr_is(
                        'input[name="task[0].output[0].name"]',
                        value => 'last_exit',
                        'task 1 output 1 name value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[0].output[0].expr"]',
                        'task 1 output 1 expr input exists',
                    );
                    $t->attr_is(
                        'input[name="task[0].output[0].expr"]',
                        value => 'exit',
                        'task 1 output 1 expr value is correct',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(1) .output :nth-child(1) button.output-remove',
                        'task 1 output 1 remove button exists',
                    );
                };
                $t->element_exists(
                    '#all-tasks > :nth-child(1) button.output-add',
                    'task 1 add output button exists',
                );
            };
        };

        subtest 'task 1 form' => sub {
            $t->element_exists(
                'input[name="task[1].class"]',
                'second plan task class input exists',
            );
            $t->attr_is(
                'input[name="task[1].class"]',
                value => 'Zapp::Task::Script',
                'second plan task class input value correct',
            );

            $t->element_exists(
                'input[name="task[1].task_id"]',
                'second plan task id input exists',
            );
            $t->attr_is(
                'input[name="task[1].task_id"]',
                value => $task_ids[1],
                'second plan task id input value correct',
            );

            $t->element_exists(
                'input[name="task[1].name"]',
                'second plan task name input exists',
            );
            $t->attr_is(
                'input[name="task[1].name"]',
                value => 'Activate the Bomb',
                'second plan task name input value correct',
            );

            $t->element_exists(
                'textarea[name="task[1].description"]',
                'second plan task description textarea exists',
            );
            $t->text_is(
                'textarea[name="task[1].description"]',
                q{Let's blow it up already!},
                'second plan task description textarea value correct',
            );

            $t->element_exists(
                '[name="task[1].input.script"]',
                'second plan task script arg exists',
            );
            $t->text_is(
                '[name="task[1].input.script"]',
                'make explosion',
                'second plan task script arg value correct',
            );

            subtest 'tests' => sub {
                subtest 'test 1' => sub {
                    $t->element_exists(
                        'input[name="task[1].tests[0].test_id"]',
                        'task 2 test 1 test_id exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].tests[0].test_id"]',
                        value => $plan->{tasks}[1]{tests}[0]{test_id},
                        'task 2 test 1 test_id value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[1].tests[0].expr"]',
                        'task 2 test 1 expr input exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].tests[0].expr"]',
                        value => 'bomb.timer',
                        'task 2 test 1 expr value is correct',
                    );
                    $t->element_exists(
                        '[name="task[1].tests[0].op"]',
                        'task 2 test 1 op field exists',
                    );
                    $t->attr_is(
                        '[name="task[1].tests[0].op"] option[selected]',
                        value => '==',
                        'task 2 test 1 op value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[1].tests[0].value"]',
                        'task 2 test 1 value field exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].tests[0].value"]',
                        value => '25:00',
                        'task 2 test 1 value value is correct',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(2) .tests > :nth-child(1) button.test-remove',
                        'task 2 test 1 remove button exists',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(2) .tests > :nth-child(1) button.test-remove',
                        'task 2 test 1 remove button exists',
                    );
                };
                subtest 'test 2' => sub {
                    $t->element_exists(
                        'input[name="task[1].tests[1].test_id"]',
                        'task 2 test 2 test_id exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].tests[1].test_id"]',
                        value => $plan->{tasks}[1]{tests}[1]{test_id},
                        'task 2 test 2 test_id value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[1].tests[1].expr"]',
                        'task 2 test 2 expr input exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].tests[1].expr"]',
                        value => 'bomb.rotation',
                        'task 2 test 2 expr value is correct',
                    );
                    $t->element_exists(
                        '[name="task[1].tests[1].op"]',
                        'task 2 test 2 op field exists',
                    );
                    $t->attr_is(
                        '[name="task[1].tests[1].op"] option[selected]',
                        value => '!=',
                        'task 2 test 2 op value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[1].tests[1].value"]',
                        'task 2 test 2 value field exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].tests[1].value"]',
                        value => '180',
                        'task 2 test 2 value value is correct',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(2) .tests > :nth-child(2) button.test-remove',
                        'task 2 test 2 remove button exists',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(2) .tests > :nth-child(2) button.test-remove',
                        'task 2 test 2 remove button exists',
                    );
                };
                $t->element_exists(
                    '#all-tasks > :nth-child(2) button.test-add',
                    'task 2 add test button exists',
                );
            };

            subtest 'output' => sub {
                subtest 'task 1' => sub {
                    $t->element_exists(
                        'input[name="task[1].output[0].name"]',
                        'task 2 output 1 name input exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].output[0].name"]',
                        value => 'last_exit',
                        'task 2 output 1 name value is correct',
                    );
                    $t->element_exists(
                        'input[name="task[1].output[0].expr"]',
                        'task 2 output 1 expr input exists',
                    );
                    $t->attr_is(
                        'input[name="task[1].output[0].expr"]',
                        value => 'exit',
                        'task 2 output 1 expr value is correct',
                    );
                    $t->element_exists(
                        '#all-tasks > :nth-child(2) .output :nth-child(1) button.output-remove',
                        'task 2 output 1 remove button exists',
                    );
                };
                $t->element_exists(
                    '#all-tasks > :nth-child(2) button.output-add',
                    'task 2 add output button exists',
                );
            };
        };

    };

    subtest 'save plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'location',
                'input[0].type' => 'string',
                'input[0].description' => 'Where to put the bomb',
                'input[0].default_value' => 'In the center',
                'input[1].name' => 'delay',
                'input[1].type' => 'number',
                'input[1].description' => 'Time to give crew to survive, in hours',
                'input[1].default_value' => '0.4',
                'task[0].task_id' => $task_ids[0],
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Build',
                'task[0].description' => 'Build a bomb',
                'task[0].input.script' => 'make thebomb',
                'task[0].tests[0].expr' => 'bomb.timer',
                'task[0].tests[0].op' => '==',
                'task[0].tests[0].value' => '25:00',
                'task[0].output[0].name' => 'last_exit',
                'task[0].output[0].expr' => 'exit',
                'task[0].output[1].name' => 'output',
                'task[0].output[1].expr' => 'stdout',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].input.script' => 'make check',
                'task[1].tests[0].expr' => 'bomb.orientation',
                'task[1].tests[0].op' => '!=',
                'task[1].tests[0].value' => 'reverse',
                'task[1].output[0].name' => 'last_exit',
                'task[1].output[0].expr' => 'exit',
            },
        );
        $t->status_is( 302 );
        $t->header_is( Location => "/plan/$plan_id" );

        my $got_plan = $t->app->yancy->get( zapp_plans => $plan_id );
        ok $got_plan, 'found plan';
        is $got_plan->{name}, 'Save NNY', 'plan name correct';
        is $got_plan->{description}, 'Save New New York City', 'plan description correct';

        my @got_tasks = $t->app->yancy->list(
            zapp_plan_tasks => {
                plan_id => $plan_id,
            },
            {
                order_by => 'task_id',
            },
        );
        is scalar @got_tasks, 2, 'got 2 tasks for plan';
        is_deeply
            {
                $got_tasks[0]->%*,
                input => decode_json( $got_tasks[0]{input} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[0],
                name => 'Build',
                description => 'Build a bomb',
                input => {
                    script => 'make thebomb',
                },
                output => [
                    { name => 'last_exit', expr => 'exit' },
                    { name => 'output', expr => 'stdout' },
                ],
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
                output => decode_json( $got_tasks[1]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                input => {
                    script => 'make check',
                },
                output => [
                    { name => 'last_exit', expr => 'exit' },
                ],
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_task_parents => {
            task_id => [ map { $_->{task_id} } @got_tasks ],
        });
        is scalar @got_parents, 1, 'got 1 relationship for plan';
        is_deeply $got_parents[0], {
            task_id => $task_ids[1],
            parent_task_id => $task_ids[0],
        };

        my @got_inputs = $t->app->yancy->list( zapp_plan_inputs =>
            {
                plan_id => $plan_id,
            },
            {
                order_by => 'name',
            },
        );
        is scalar @got_inputs, 2, 'got 2 inputs for plan';
        is_deeply $got_inputs[0], {
            plan_id => $plan_id,
            name => 'delay',
            type => 'number',
            description => 'Time to give crew to survive, in hours',
            default_value => encode_json( '0.4' ),
        };
        is_deeply $got_inputs[1], {
            plan_id => $plan_id,
            name => 'location',
            type => 'string',
            description => 'Where to put the bomb',
            default_value => encode_json( 'In the center' ),
        };

        my @got_tests = $t->app->yancy->list(
            zapp_plan_tests => {
                plan_id => $plan_id,
            },
            {
                order_by => [ qw( test_id task_id ) ],
            },
        );
        is scalar @got_tests, 2, 'got 2 tests for plan';
        is_deeply $got_tests[0],
            {
                test_id => $got_tests[0]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[0]{task_id},
                expr => 'bomb.timer',
                op => '==',
                value => '25:00',
            },
            'task 1 test 1 is correct';
        is_deeply $got_tests[1],
            {
                test_id => $got_tests[1]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[1]{task_id},
                expr => 'bomb.orientation',
                op => '!=',
                value => 'reverse',
            },
            'task 2 test 1 is correct';
    };

    subtest 'add task to plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'location',
                'input[0].type' => 'string',
                'input[0].description' => 'Where to put the bomb',
                'input[0].default_value' => 'In the center',
                'input[1].name' => 'delay',
                'input[1].type' => 'number',
                'input[1].description' => 'Time to give crew to survive, in hours',
                'input[1].default_value' => '0.4',
                'task[0].task_id' => $task_ids[0],
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Build',
                'task[0].description' => 'Build a bomb',
                'task[0].input.script' => 'make thebomb',
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Transit',
                'task[1].description' => 'Fly to garbage ball',
                'task[1].input.script' => 'make flight',
                'task[2].task_id' => $task_ids[1],
                'task[2].class' => 'Zapp::Task::Script',
                'task[2].name' => 'Verify Bomb',
                'task[2].description' => 'Make sure this time',
                'task[2].input.script' => 'make check',
                'task[2].tests[0].expr' => 'bomb.orientation',
                'task[2].tests[0].op' => '!=',
                'task[2].tests[0].value' => 'reverse',
            },
        );
        $t->status_is( 302 );
        $t->header_is( Location => "/plan/$plan_id" );

        my @got_tasks = $t->app->yancy->list(
            zapp_plan_tasks => {
                plan_id => $plan_id,
            },
            {
                order_by => 'task_id',
            },
        );
        is scalar @got_tasks, 3, 'got 3 tasks for plan';

        is_deeply
            {
                $got_tasks[0]->%*,
                input => decode_json( $got_tasks[0]{input} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[0],
                name => 'Build',
                description => 'Build a bomb',
                input => {
                    script => 'make thebomb',
                },
                output => [],
            },
            'task 1 is correct';

        is_deeply
            {
                $got_tasks[2]->%*,
                input => decode_json( $got_tasks[2]{input} ),
                output => decode_json( $got_tasks[2]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $got_tasks[2]{task_id},
                name => 'Transit',
                description => 'Fly to garbage ball',
                input => {
                    script => 'make flight',
                },
                output => [],
            },
            'new task is correct';

        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
                output => decode_json( $got_tasks[1]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                input => {
                    script => 'make check',
                },
                output => [],
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_task_parents =>
            {
                task_id => [ map { $_->{task_id} } @got_tasks ],
            },
            {
                order_by => 'task_id',
            },
        );
        is scalar @got_parents, 2, 'got 2 relationships for plan';

        is_deeply $got_parents[0], {
            task_id => $task_ids[1],
            parent_task_id => $got_tasks[2]{task_id},
        };
        is_deeply $got_parents[1], {
            task_id => $got_tasks[2]{task_id},
            parent_task_id => $task_ids[0],
        };

        my @got_inputs = $t->app->yancy->list( zapp_plan_inputs =>
            {
                plan_id => $plan_id,
            },
            {
                order_by => 'name',
            },
        );
        is scalar @got_inputs, 2, 'got 2 inputs for plan';
        is_deeply $got_inputs[0], {
            plan_id => $plan_id,
            name => 'delay',
            type => 'number',
            description => 'Time to give crew to survive, in hours',
            default_value => encode_json( '0.4' ),
        };
        is_deeply $got_inputs[1], {
            plan_id => $plan_id,
            name => 'location',
            type => 'string',
            description => 'Where to put the bomb',
            default_value => encode_json( 'In the center' ),
        };

        my @got_tests = $t->app->yancy->list(
            zapp_plan_tests => {
                plan_id => $plan_id,
            },
            {
                order_by => [ qw( test_id task_id ) ],
            },
        );
        is scalar @got_tests, 2, 'got 2 tests for plan';
        is_deeply $got_tests[0],
            {
                test_id => $got_tests[0]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[0]{task_id},
                expr => 'bomb.timer',
                op => '==',
                value => '25:00',
            },
            'task 1 test 1 is correct';
        is_deeply $got_tests[1],
            {
                test_id => $got_tests[1]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[1]{task_id},
                expr => 'bomb.orientation',
                op => '!=',
                value => 'reverse',
            },
            'task 2 test 1 is correct';
    };

    subtest 'remove task from plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'prank_name',
                'input[0].type' => 'string',
                'input[0].description' => 'A funny name to demoralize the Mighty One',
                'input[0].default_value' => 'I.C. Weiner',
                'input[1].name' => 'delay',
                'input[1].type' => 'number',
                'input[1].description' => 'Time to give crew to survive, in hours',
                'input[1].default_value' => '0.4',
                'task[0].task_id' => $task_ids[0],
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Build',
                'task[0].description' => 'Build a bomb',
                'task[0].input.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].input.script' => 'make check',
                'task[1].tests[0].expr' => 'bomb.orientation',
                'task[1].tests[0].op' => '!=',
                'task[1].tests[0].value' => 'reverse',
            },
        );
        $t->status_is( 302 );
        $t->header_is( Location => "/plan/$plan_id" );

        my @got_tasks = $t->app->yancy->list(
            zapp_plan_tasks => {
                plan_id => $plan_id,
            },
            {
                order_by => 'task_id',
            },
        );
        is scalar @got_tasks, 2, 'got 2 tasks for plan';

        is_deeply
            {
                $got_tasks[0]->%*,
                input => decode_json( $got_tasks[0]{input} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[0],
                name => 'Build',
                description => 'Build a bomb',
                input => {
                    script => 'make thebomb',
                },
                output => [],
            },
            'task 1 is correct';

        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
                output => decode_json( $got_tasks[1]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                input => {
                    script => 'make check',
                },
                output => [],
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_task_parents => {
            task_id => [ map { $_->{task_id} } @got_tasks ],
        });
        is scalar @got_parents, 1, 'got 1 relationship for plan';
        is_deeply $got_parents[0], {
            task_id => $task_ids[1],
            parent_task_id => $task_ids[0],
        };

        my @got_tests = $t->app->yancy->list(
            zapp_plan_tests => {
                plan_id => $plan_id,
            },
            {
                order_by => [ qw( test_id task_id ) ],
            },
        );
        is scalar @got_tests, 2, 'got 2 tests for plan';
        is_deeply $got_tests[0],
            {
                test_id => $got_tests[0]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[0]{task_id},
                expr => 'bomb.timer',
                op => '==',
                value => '25:00',
            },
            'task 1 test 1 is correct';
        is_deeply $got_tests[1],
            {
                test_id => $got_tests[1]{test_id},
                plan_id => $plan_id,
                task_id => $got_tasks[1]{task_id},
                expr => 'bomb.orientation',
                op => '!=',
                value => 'reverse',
            },
            'task 2 test 1 is correct';
    };

    subtest 'remove input from plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'delay',
                'input[0].type' => 'number',
                'input[0].description' => 'Time to give crew to survive, in minutes',
                'input[0].default_value' => '60',
                'task[0].task_id' => $task_ids[0],
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Build',
                'task[0].description' => 'Build a bomb',
                'task[0].input.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].input.script' => 'make check',
                'task[1].tests[0].expr' => 'bomb.orientation',
                'task[1].tests[0].op' => '!=',
                'task[1].tests[0].value' => 'reverse',
            },
        );
        $t->status_is( 302 );
        $t->header_is( Location => "/plan/$plan_id" );

        my @got_inputs = $t->app->yancy->list( zapp_plan_inputs =>
            {
                plan_id => $plan_id,
            },
            {
                order_by => 'name',
            },
        );
        is scalar @got_inputs, 1, 'got 1 inputs for plan';
        is_deeply $got_inputs[0], {
            plan_id => $plan_id,
            name => 'delay',
            type => 'number',
            description => 'Time to give crew to survive, in minutes',
            default_value => encode_json( '60' ),
        };
    };

    subtest 'add input to plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'delay',
                'input[0].type' => 'number',
                'input[0].description' => 'Time to give crew to survive, in minutes',
                'input[0].default_value' => '60',
                'input[1].name' => 'location',
                'input[1].type' => 'string',
                'input[1].description' => 'Where to place the bomb',
                'input[1].default_value' => 'In the center',
                'task[0].task_id' => $task_ids[0],
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Build',
                'task[0].description' => 'Build a bomb',
                'task[0].input.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].input.script' => 'make check',
                'task[1].tests[0].expr' => 'bomb.orientation',
                'task[1].tests[0].op' => '!=',
                'task[1].tests[0].value' => 'reverse',
            },
        );
        $t->status_is( 302 );
        $t->header_is( Location => "/plan/$plan_id" );

        my @got_inputs = $t->app->yancy->list( zapp_plan_inputs =>
            {
                plan_id => $plan_id,
            },
            {
                order_by => 'name',
            },
        );
        is scalar @got_inputs, 2, 'got 1 inputs for plan';
        is_deeply $got_inputs[0], {
            plan_id => $plan_id,
            name => 'delay',
            type => 'number',
            description => 'Time to give crew to survive, in minutes',
            default_value => encode_json( '60' ),
        };
        is_deeply $got_inputs[1], {
            plan_id => $plan_id,
            name => 'location',
            type => 'string',
            description => 'Where to place the bomb',
            default_value => encode_json( 'In the center' ),
        };
    };

};

subtest 'list plans' => sub {
    $t->Test::Yancy::clear_backend;
    my @plans = (
        $t->app->create_plan({
            name => 'Deliver a package',
            description => 'To a dangerous place',
        }),
        $t->app->create_plan({
            name => 'Clean the ship',
            description => 'Of any remains of the crew',
        }),
        $t->app->create_plan({
            name => 'Find a replacement crew',
            description => 'After their inevitable deaths',
        }),
    );

    $t->get_ok( '/' )->status_is( 200 )
        ->text_like( '.plans-list > :nth-child(1) h2', qr{Deliver a package} )
        ->text_like( '.plans-list > :nth-child(1) .description', qr{To a dangerous place} )
        ->element_exists( '.plans-list > :nth-child(1) a.run', 'run button exists' )
        ->attr_is( '.plans-list > :nth-child(1) a.run', href => '/plan/' . $plans[0]{plan_id} . '/run' )
        ->element_exists( '.plans-list > :nth-child(1) a.edit', 'edit button exists' )
        ->attr_is( '.plans-list > :nth-child(1) a.edit', href => '/plan/' . $plans[0]{plan_id} )
        ->element_exists( '.plans-list > :nth-child(1) a.delete', 'delete button exists' )
        ->attr_is( '.plans-list > :nth-child(1) a.delete', href => '/plan/' . $plans[0]{plan_id} . '/delete' )

        ->text_like( '.plans-list > :nth-child(2) h2', qr{Clean the ship} )
        ->text_like( '.plans-list > :nth-child(2) .description', qr{Of any remains of the crew} )
        ->element_exists( '.plans-list > :nth-child(2) a.run', 'run button exists' )
        ->attr_is( '.plans-list > :nth-child(2) a.run', href => '/plan/' . $plans[1]{plan_id} . '/run' )
        ->element_exists( '.plans-list > :nth-child(2) a.edit', 'edit button exists' )
        ->attr_is( '.plans-list > :nth-child(2) a.edit', href => '/plan/' . $plans[1]{plan_id} )
        ->element_exists( '.plans-list > :nth-child(2) a.delete', 'delete button exists' )
        ->attr_is( '.plans-list > :nth-child(2) a.delete', href => '/plan/' . $plans[1]{plan_id} . '/delete' )

        ->text_like( '.plans-list > :nth-child(3) h2', qr{Find a replacement crew} )
        ->text_like( '.plans-list > :nth-child(3) .description', qr{After their inevitable deaths} )
        ->element_exists( '.plans-list > :nth-child(3) a.run', 'run button exists' )
        ->attr_is( '.plans-list > :nth-child(3) a.run', href => '/plan/' . $plans[2]{plan_id} . '/run' )
        ->element_exists( '.plans-list > :nth-child(3) a.edit', 'edit button exists' )
        ->attr_is( '.plans-list > :nth-child(3) a.edit', href => '/plan/' . $plans[2]{plan_id} )
        ->element_exists( '.plans-list > :nth-child(3) a.delete', 'delete button exists' )
        ->attr_is( '.plans-list > :nth-child(3) a.delete', href => '/plan/' . $plans[2]{plan_id} . '/delete' )
        ;
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
                default_value => encode_json( 'Chapek 9' ),
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
            ->attr_is( '[name="input[0].value"]', value => 'Chapek 9', 'input value is correct' )
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
        is_deeply decode_json( $run->{input_values} ),
            {
                destination => {
                    type => 'string',
                    value => 'Galaxy of Terror',
                },
            },
            'run input is correct';

        # Record all enqueued jobs so we can keep track of which Minion
        # jobs were triggered by which Zapp run
        my @jobs = $t->app->yancy->list(
            zapp_run_jobs => { run_id => $run_id },
            { order_by => { -asc => 'minion_job_id' } },
        );
        is scalar @jobs, 2, 'two run jobs created';
        is_deeply
            {
                $jobs[0]->%*,
                context => decode_json( $jobs[0]{context} ),
            },
            {
                $jobs[0]->%{qw( minion_job_id )},
                context => {
                    destination => {
                        type => 'string',
                        value => 'Galaxy of Terror',
                    },
                },
                run_id => $run_id,
                task_id => $plan->{tasks}[0]{task_id},
                state => 'inactive',
            },
            'first job is correct'
                or diag explain $jobs[0];
        is_deeply
            {
                $jobs[1]->%*,
                context => decode_json( $jobs[1]{context} ),
            },
            {
                $jobs[1]->%{qw( minion_job_id )},
                context => {},
                run_id => $run_id,
                task_id => $plan->{tasks}[1]{task_id},
                state => 'inactive',
            },
            'second job is correct'
                or diag explain $jobs[1];

        # Tests are copied to allow modifying job
        my @tests = $t->app->yancy->list(
            zapp_run_tests => { run_id => $run_id },
            { order_by => [ 'task_id', 'test_id' ] },
        );
        is scalar @tests, 3, 'three run tests created';
        is_deeply $tests[0],
            {
                run_id => $run_id,
                task_id => $jobs[0]{task_id},
                test_id => $plan->{tasks}[0]{tests}[0]{test_id},
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
                task_id => $jobs[1]{task_id},
                test_id => $plan->{tasks}[1]{tests}[0]{test_id},
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
                task_id => $jobs[1]{task_id},
                test_id => $plan->{tasks}[1]{tests}[1]{test_id},
                expr => 'exit',
                op => '==',
                value => '0',
                pass => undef,
                expr_value => undef,
            },
            'run task 2 test 2 is correct';

        # Enqueued in Minion
        my $mjob = $t->app->minion->job( $jobs[0]{minion_job_id} );
        ok $mjob, 'minion job 1 exists';
        # XXX: Test job attributes

        $mjob = $t->app->minion->job( $jobs[1]{minion_job_id} );
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
                default_value => encode_json( 'Leela' ),
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
        $job = $t->app->yancy->get( zapp_run_jobs => $run->{jobs}[1] );
        is $job->{state}, 'stopped', 'zapp job state is correct'
            or diag explain [ $run->{jobs}[1], $job ];

        # Minion job removed
        ok !$t->app->minion->job( $run->{jobs}[1] ), 'minion job removed';

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
        $run->{jobs} = [
            map { $_->{minion_job_id} }
            $t->app->yancy->list( zapp_run_jobs => { $run->%{'run_id'} } )
        ];
        ; diag 'New jobs: ' . explain $run->{jobs};

        # Zapp job state "inactive"
        $job = $t->app->yancy->get( zapp_run_jobs => $run->{jobs}[1] );
        is $job->{state}, 'inactive', 'zapp job state is correct';

        # Minion job state "inactive"
        $job = $t->app->minion->job( $run->{jobs}[1] );
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

        # Zapp job state "killed"
        $job = $t->app->yancy->get( zapp_run_jobs => $run->{jobs}[1] );
        is $job->{state}, 'killed', 'zapp job state is correct';

        # Minion job removed
        ok !$t->app->minion->job( $run->{jobs}[1] ), 'minion job removed';

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

subtest 'delete plan' => sub {
    my $plan = $t->app->create_plan({
        name => 'Cut Ribbon at DOOP Headquarters',
        tasks => [
            {
                name => 'Get Ceremonial Oversized Scissors',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo What makes a man turn neutral?',
                }),
                tests => [
                    {
                        expr => 'sharpness',
                        op => '>',
                        value => 'dull',
                    },
                ],
            },
        ],
        inputs => [
            {
                name => 'color',
                type => 'string',
                description => 'What color of scissors',
                default_value => encode_json( 'White' ),
            },
        ],
    });
    my $plan_id = $plan->{plan_id};
    $t->get_ok( "/plan/$plan_id/delete" )->status_is( 200 )
        ->content_like( qr{Cut Ribbon at DOOP Headquarters}, 'content contains plan name' )
        ->element_exists( '.alert form', 'form exists in alert' )
        ->attr_is( '.alert form', action => "/plan/$plan_id/delete", 'form url is correct' )
        ->attr_is( '.alert form', method => 'POST', 'form method is correct' )
        ->element_exists( 'a[href].cancel', 'cancel link exists' )
        ->attr_is( 'a[href].cancel', href => '/', 'cancel link href correct (back to plan list)' )
        ;
    ok $t->app->yancy->get( zapp_plans => $plan_id ), 'plan still exists';
    ok $t->app->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } ), 'plan tasks still exist';
    ok $t->app->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } ), 'plan inputs still exist';
    ok $t->app->yancy->list( zapp_plan_tests => { plan_id => $plan_id } ), 'plan tests still exist';

    $t->post_ok( "/plan/$plan_id/delete" )->status_is( 302, 'delete success redirects' )
        ->header_is( Location => '/', 'redirects to plan list' )
        ;
    ok !$t->app->yancy->get( zapp_plans => $plan_id ), 'plan does not exist';
    ok !$t->app->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } ), 'plan tasks deleted'
        or diag explain $t->app->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } );
    ok !$t->app->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } ), 'plan inputs deleted'
        or diag explain $t->app->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } );
    ok !$t->app->yancy->list( zapp_plan_tests => { plan_id => $plan_id } ), 'plan tests deleted'
        or diag explain $t->app->yancy->list( zapp_plan_tests => { plan_id => $plan_id } );
};

subtest 'error - input name invalid' => sub {
    $t->post_ok( "/plan",
        form => {
            name => 'Get Rich Quick x7q',
            'input[0].name' => '}h3l:(){',
            'input[0].type' => 'string',
        },
    )
        ->status_is( 400 )
        ->text_like( '.alert.alert-danger li:nth-child(1)' => qr/Input name "\}h3l:\(\)\{" has invalid characters:/ )
        ->text_is( '.alert.alert-danger li:nth-child(1) kbd:nth-of-type(1)' => '(' )
        ->text_is( '.alert.alert-danger li:nth-child(1) kbd:nth-of-type(2)' => ')' )
        ->text_is( '.alert.alert-danger li:nth-child(1) kbd:nth-of-type(3)' => ':' )
        ->text_is( '.alert.alert-danger li:nth-child(1) kbd:nth-of-type(4)' => '{' )
        ->text_is( '.alert.alert-danger li:nth-child(1) kbd:nth-of-type(5)' => '}' )
        ;
};

done_testing;

sub Test::Yancy::clear_backend {
    my ( $self ) = @_;
    my %tables = (
        zapp_plans => 'plan_id',
        zapp_plan_inputs => [ 'plan_id', 'name' ],
        zapp_plan_tasks => 'task_id',
        zapp_task_parents => 'task_id',
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

