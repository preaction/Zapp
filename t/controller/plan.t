
=head1 DESCRIPTION

This tests Zapp::Controller::Plan (except for the JavaScript involved).

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
            ->text_is(
                'select.add-task option:nth-child(2)',
                'Assert',
                'first task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(2)',
                value => 'Zapp::Task::Assert',
                'first task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(3)',
                'Echo',
                'second task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(3)',
                value => 'Zapp::Task::Echo',
                'second task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(4)',
                'Request',
                'third task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(4)',
                value => 'Zapp::Task::Request',
                'third task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(5)',
                'Script',
                'fourth task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(5)',
                value => 'Zapp::Task::Script',
                'fourth task option value is correct',
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
                'task[0].args.script' => 'make order',
                'task[1].class' => 'Zapp::Task::Assert',
                'task[1].name' => 'Verify',
                'task[1].description' => 'Verify freezer',
                'task[1].args[0].expr' => 'timer',
                'task[1].args[0].op' => '>=',
                'task[1].args[0].value' => '1000 years',
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
                args => decode_json( $got_tasks[0]{args} ),
            },
            {
                plan_id => $got_plan->{plan_id},
                task_id => $got_tasks[0]{task_id},
                class =>'Zapp::Task::Script',
                name => 'Order pizza',
                description => 'I.C. Weiner',
                args => {
                    script => 'make order',
                },
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                args => decode_json( $got_tasks[1]{args} ),
            },
            {
                plan_id => $got_plan->{plan_id},
                task_id => $got_tasks[1]{task_id},
                class =>'Zapp::Task::Assert',
                name => 'Verify',
                description => 'Verify freezer',
                args => [
                    {
                        expr => 'timer',
                        op => '>=',
                        value => '1000 years',
                    },
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
                args => encode_json({
                    script => "liftoff;\ndrop the_bomb\n",
                }),
            },
            {
                name => 'Verify bomb placement',
                description => q{Let's blow it up already!},
                class => 'Zapp::Task::Assert',
                args => encode_json([
                    {
                        expr => 'bomb.timer',
                        op => '==',
                        value => '25:00',
                    },
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
            ->text_is(
                'select.add-task option:nth-child(2)',
                'Assert',
                'first task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(2)',
                value => 'Zapp::Task::Assert',
                'first task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(3)',
                'Echo',
                'second task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(3)',
                value => 'Zapp::Task::Echo',
                'second task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(4)',
                'Request',
                'third task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(4)',
                value => 'Zapp::Task::Request',
                'third task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(5)',
                'Script',
                'fourth task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(5)',
                value => 'Zapp::Task::Script',
                'fourth task option value is correct',
            )
            ;

        subtest 'inputs form' => sub {
            $t->element_exists(
                '[name="input[0].name"]',
                'first input name input exists',
            );
            $t->attr_is(
                '[name="input[0].name"]',
                value => 'delay',
                'first input name input value is correct',
            );
            $t->element_exists(
                '[name="input[0].type"]',
                'first input type input exists',
            );
            $t->attr_is(
                '[name="input[0].type"]',
                value => 'number',
                'first input type input value is correct',
            );
            $t->element_exists(
                '[name="input[0].description"]',
                'first input description input exists',
            );
            $t->text_is(
                '[name="input[0].description"]',
                'Time to give crew to survive, in minutes',
                'first input description input value is correct',
            );
            $t->element_exists(
                '[name="input[0].default_value"]',
                'first input default input exists',
            );
            $t->attr_is(
                '[name="input[0].default_value"]',
                value => '25',
                'first input default value input value is correct',
            );

            $t->element_exists(
                '[name="input[1].name"]',
                'second input name input exists',
            );
            $t->attr_is(
                '[name="input[1].name"]',
                value => 'location',
                'second input name input value is correct',
            );
            $t->element_exists(
                '[name="input[1].type"]',
                'second input type input exists',
            );
            $t->attr_is(
                '[name="input[1].type"]',
                value => 'string',
                'second input type input value is correct',
            );
            $t->element_exists(
                '[name="input[1].description"]',
                'second input description input exists',
            );
            $t->text_is(
                '[name="input[1].description"]',
                'Where to place the bomb',
                'second input description input value is correct',
            );
            $t->element_exists(
                '[name="input[1].default_value"]',
                'second input default input exists',
            );
            $t->attr_is(
                '[name="input[1].default_value"]',
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
                'textarea[name="task[0].args.script"]',
                'task script textarea exists',
            );
            $t->text_is(
                'textarea[name="task[0].args.script"]',
                "liftoff;\ndrop the_bomb\n",
                'first plan task description textarea value correct',
            );

        };

        subtest 'task 1 form' => sub {
            $t->element_exists(
                'input[name="task[1].class"]',
                'second plan task class input exists',
            );
            $t->attr_is(
                'input[name="task[1].class"]',
                value => 'Zapp::Task::Assert',
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
                value => 'Verify bomb placement',
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
                'input[name="task[1].args[0].expr"]',
                'second plan task first arg expr input exists',
            );
            $t->attr_is(
                'input[name="task[1].args[0].expr"]',
                value => 'bomb.timer',
                'second plan task first arg expr input value correct',
            );

            $t->element_exists(
                'select[name="task[1].args[0].op"]',
                'second plan task first arg op select exists',
            );
            $t->text_is(
                'select[name="task[1].args[0].op"] [selected]',
                '==',
                'second plan task first arg op select value correct',
            );

            $t->element_exists(
                'input[name="task[1].args[0].value"]',
                'second plan task first arg value input exists',
            );
            $t->attr_is(
                'input[name="task[1].args[0].value"]',
                value => '25:00',
                'second plan task first arg value input value correct',
            );
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
                'task[0].args.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Assert',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].args[0].expr' => 'bomb.orientation',
                'task[1].args[0].op' => '!=',
                'task[1].args[0].value' => 'reverse',
                'task[1].args[1].expr' => 'bomb.timer',
                'task[1].args[1].op' => '==',
                'task[1].args[1].value' => '25:00',
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
                args => decode_json( $got_tasks[0]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[0],
                name => 'Build',
                description => 'Build a bomb',
                args => {
                    script => 'make thebomb',
                },
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                args => decode_json( $got_tasks[1]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Assert',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                args => [
                    {
                        expr => 'bomb.orientation',
                        op => '!=',
                        value => 'reverse',
                    },
                    {
                        expr => 'bomb.timer',
                        op => '==',
                        value => '25:00',
                    },
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
                'task[0].args.script' => 'make thebomb',
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Transit',
                'task[1].description' => 'Fly to garbage ball',
                'task[1].args.script' => 'make flight',
                'task[2].task_id' => $task_ids[1],
                'task[2].class' => 'Zapp::Task::Assert',
                'task[2].name' => 'Verify Bomb',
                'task[2].description' => 'Make sure this time',
                'task[2].args[0].expr' => 'bomb.orientation',
                'task[2].args[0].op' => '!=',
                'task[2].args[0].value' => 'reverse',
                'task[2].args[1].expr' => 'bomb.timer',
                'task[2].args[1].op' => '==',
                'task[2].args[1].value' => '25:00',
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
                args => decode_json( $got_tasks[0]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[0],
                name => 'Build',
                description => 'Build a bomb',
                args => {
                    script => 'make thebomb',
                },
            },
            'task 1 is correct';

        is_deeply
            {
                $got_tasks[2]->%*,
                args => decode_json( $got_tasks[2]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $got_tasks[2]{task_id},
                name => 'Transit',
                description => 'Fly to garbage ball',
                args => {
                    script => 'make flight',
                },
            },
            'new task is correct';

        is_deeply
            {
                $got_tasks[1]->%*,
                args => decode_json( $got_tasks[1]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Assert',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                args => [
                    {
                        expr => 'bomb.orientation',
                        op => '!=',
                        value => 'reverse',
                    },
                    {
                        expr => 'bomb.timer',
                        op => '==',
                        value => '25:00',
                    },
                ],
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_task_parents => {
            task_id => [ map { $_->{task_id} } @got_tasks ],
        });
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
                'task[0].args.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Assert',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].args[0].expr' => 'bomb.orientation',
                'task[1].args[0].op' => '!=',
                'task[1].args[0].value' => 'reverse',
                'task[1].args[1].expr' => 'bomb.timer',
                'task[1].args[1].op' => '==',
                'task[1].args[1].value' => '25:00',
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
                args => decode_json( $got_tasks[0]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[0],
                name => 'Build',
                description => 'Build a bomb',
                args => {
                    script => 'make thebomb',
                },
            },
            'task 1 is correct';

        is_deeply
            {
                $got_tasks[1]->%*,
                args => decode_json( $got_tasks[1]{args} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Assert',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                args => [
                    {
                        expr => 'bomb.orientation',
                        op => '!=',
                        value => 'reverse',
                    },
                    {
                        expr => 'bomb.timer',
                        op => '==',
                        value => '25:00',
                    },
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
                'task[0].args.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Assert',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].args[0].expr' => 'bomb.orientation',
                'task[1].args[0].op' => '!=',
                'task[1].args[0].value' => 'reverse',
                'task[1].args[1].expr' => 'bomb.timer',
                'task[1].args[1].op' => '==',
                'task[1].args[1].value' => '25:00',
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
                'task[0].args.script' => 'make thebomb',
                'task[1].task_id' => $task_ids[1],
                'task[1].class' => 'Zapp::Task::Assert',
                'task[1].name' => 'Verify Bomb',
                'task[1].description' => 'Make sure this time',
                'task[1].args[0].expr' => 'bomb.orientation',
                'task[1].args[0].op' => '!=',
                'task[1].args[0].value' => 'reverse',
                'task[1].args[1].expr' => 'bomb.timer',
                'task[1].args[1].op' => '==',
                'task[1].args[1].value' => '25:00',
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
        ->text_like( 'section:nth-child(1) h2', qr{Deliver a package} )
        ->text_like( 'section:nth-child(1) .description', qr{To a dangerous place} )
        ->element_exists( 'section:nth-child(1) a.run', 'run button exists' )
        ->attr_is( 'section:nth-child(1) a.run', href => '/plan/' . $plans[0]{plan_id} . '/run/' )
        ->element_exists( 'section:nth-child(1) a.edit', 'edit button exists' )
        ->attr_is( 'section:nth-child(1) a.edit', href => '/plan/' . $plans[0]{plan_id} )

        ->text_like( 'section:nth-child(2) h2', qr{Clean the ship} )
        ->text_like( 'section:nth-child(2) .description', qr{Of any remains of the crew} )
        ->element_exists( 'section:nth-child(2) a.run', 'run button exists' )
        ->attr_is( 'section:nth-child(2) a.run', href => '/plan/' . $plans[1]{plan_id} . '/run/' )
        ->element_exists( 'section:nth-child(2) a.edit', 'edit button exists' )
        ->attr_is( 'section:nth-child(2) a.edit', href => '/plan/' . $plans[1]{plan_id} )

        ->text_like( 'section:nth-child(3) h2', qr{Find a replacement crew} )
        ->text_like( 'section:nth-child(3) .description', qr{After their inevitable deaths} )
        ->element_exists( 'section:nth-child(3) a.run', 'run button exists' )
        ->attr_is( 'section:nth-child(3) a.run', href => '/plan/' . $plans[2]{plan_id} . '/run/' )
        ->element_exists( 'section:nth-child(3) a.edit', 'edit button exists' )
        ->attr_is( 'section:nth-child(3) a.edit', href => '/plan/' . $plans[2]{plan_id} )
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
                class => 'Zapp::Task::Echo',
                args => encode_json({
                    destination => 'Chapek 9',
                }),
            },
            {
                name => 'Deliver package',
                class => 'Zapp::Task::Echo',
                args => encode_json({
                    delivery_address => 'Certain Doom',
                }),
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
            ->element_exists( "form[action=/plan/$plan_id/run", 'form exists' )
            ->element_exists( '[name=input.destination]', 'input field exists' )
            ;
    };

    subtest 'create a new run' => sub {
        $t->post_ok(
            "/plan/$plan_id/run",
            form => {
                'input.destination' => 'Galaxy of Terror',
            } )
            ->status_is( 302 )->or( $dump_debug )
            ->header_like( Location => qr{/plan/$plan_id/run/\d+} )
            ;
        my ( $run_id ) = $t->tx->res->headers->location =~ m{/plan/\d+/run/(\d+)};

        # Recorded in Zapp
        my $run = $t->app->yancy->get( zapp_runs => $run_id );
        is $run->{plan_id}, $plan_id, 'run plan_id is correct';
        is_deeply decode_json( $run->{input_values} ), { destination => 'Galaxy of Terror' },
            'run input is correct';

        # Record all enqueued jobs so we can keep track of which Minion
        # jobs were triggered by which Zapp run
        my @jobs = $t->app->yancy->list(
            zapp_run_jobs => { run_id => $run_id },
            { order_by => { -asc => 'minion_job_id' } },
        );
        is scalar @jobs, 2, 'two run jobs created';

        # Enqueued in Minion
        my $mjob = $t->app->minion->job( $jobs[0]{minion_job_id} );
        ok $mjob, 'minion job 1 exists';
        # XXX: Test job attributes

        $mjob = $t->app->minion->job( $jobs[1]{minion_job_id} );
        ok $mjob, 'minion job 2 exists';
        # XXX: Test job attributes
    };

    subtest 'view run status' => sub {
        subtest 'before execution' => sub {
            pass 'todo';
        };

        subtest 'after execution' => sub {
            pass 'todo';
        };
    };

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

