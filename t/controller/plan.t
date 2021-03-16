
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
                'input[0].config' => 'I.C. Weiner',
                'task[0].class' => 'Zapp::Task::Script',
                'task[0].name' => 'Order pizza',
                'task[0].description' => 'I.C. Weiner',
                'task[0].input.script' => 'echo make order',
                'task[1].class' => 'Zapp::Task::Script',
                'task[1].name' => 'Verify',
                'task[1].description' => 'Verify freezer',
                'task[1].input.script' => 'echo make test',
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
            },
            {
                plan_id => $got_plan->{plan_id},
                task_id => $got_tasks[0]{task_id},
                class =>'Zapp::Task::Script',
                name => 'Order pizza',
                description => 'I.C. Weiner',
                input => {
                    script => 'echo make order',
                },
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
            },
            {
                plan_id => $got_plan->{plan_id},
                task_id => $got_tasks[1]{task_id},
                class =>'Zapp::Task::Script',
                name => 'Verify',
                description => 'Verify freezer',
                input => {
                    script => 'echo make test',
                },
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_plan_task_parents => {
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
            rank => 0,
            type => 'string',
            description => 'A funny name to demoralize the Mighty One',
            config => encode_json( 'I.C. Weiner' ),
            value => encode_json( undef ),
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
                input => encode_json({
                    script => "liftoff;\ndrop the_bomb\n",
                }),
            },
            {
                name => 'Activate the Bomb',
                description => q{Let's blow it up already!},
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => "make explosion",
                }),
            },
        ],
        inputs => [
            {
                name => 'delay',
                type => 'number',
                description => 'Time to give crew to survive, in minutes',
                config => encode_json( 25 ),
            },
            {
                name => 'location',
                type => 'string',
                description => 'Where to place the bomb',
                config => encode_json( 'In the center' ),
            },
        ],
    } );
    my $plan_id = $plan->{plan_id};
    my @task_ids = map { $_->{task_id} } @{ $plan->{tasks} };

    subtest 'edit plan form' => sub {
        $t->get_ok( "/plan/$plan_id" )->status_is( 200 );
        $t->$dump_debug;
        $t->element_exists( 'form#plan', 'form exists' )
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
                'form [name="input[0].config"]',
                'first input default input exists',
            );
            $t->attr_is(
                'form [name="input[0].config"]',
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
                'form [name="input[1].config"]',
                'second input default input exists',
            );
            $t->attr_is(
                'form [name="input[1].config"]',
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

        };

    };

    subtest 'save plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'delay',
                'input[0].type' => 'number',
                'input[0].description' => 'Time to give crew to survive, in hours',
                'input[0].config' => '0.4',
                'input[1].name' => 'location',
                'input[1].type' => 'string',
                'input[1].description' => 'Where to put the bomb',
                'input[1].config' => 'In the center',
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
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
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
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_plan_task_parents => {
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
            rank => 0,
            type => 'number',
            description => 'Time to give crew to survive, in hours',
            config => encode_json( '0.4' ),
            value => encode_json( undef ),
        };
        is_deeply $got_inputs[1], {
            plan_id => $plan_id,
            name => 'location',
            rank => 1,
            type => 'string',
            description => 'Where to put the bomb',
            config => encode_json( 'In the center' ),
            value => encode_json( undef ),
        };

    };

    subtest 'add task to plan' => sub {
        $t->post_ok( "/plan/$plan_id",
            form => {
                name => 'Save NNY',
                description => 'Save New New York City',
                'input[0].name' => 'delay',
                'input[0].type' => 'number',
                'input[0].description' => 'Time to give crew to survive, in hours',
                'input[0].config' => '0.4',
                'input[1].name' => 'location',
                'input[1].type' => 'string',
                'input[1].description' => 'Where to put the bomb',
                'input[1].config' => 'In the center',
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
            },
            'task 1 is correct';

        is_deeply
            {
                $got_tasks[2]->%*,
                input => decode_json( $got_tasks[2]{input} ),
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
            },
            'new task is correct';

        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
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
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_plan_task_parents =>
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
            rank => 0,
            type => 'number',
            description => 'Time to give crew to survive, in hours',
            config => encode_json( '0.4' ),
            value => encode_json( undef ),
        };
        is_deeply $got_inputs[1], {
            plan_id => $plan_id,
            name => 'location',
            rank => 1,
            type => 'string',
            description => 'Where to put the bomb',
            config => encode_json( 'In the center' ),
            value => encode_json( undef ),
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
                'input[0].config' => 'I.C. Weiner',
                'input[1].name' => 'delay',
                'input[1].type' => 'number',
                'input[1].description' => 'Time to give crew to survive, in hours',
                'input[1].config' => '0.4',
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
            },
            'task 1 is correct';

        is_deeply
            {
                $got_tasks[1]->%*,
                input => decode_json( $got_tasks[1]{input} ),
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
            },
            'task 2 is correct';

        my @got_parents = $t->app->yancy->list( zapp_plan_task_parents => {
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
                'input[0].config' => '60',
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
            rank => 0,
            type => 'number',
            description => 'Time to give crew to survive, in minutes',
            config => encode_json( '60' ),
            value => encode_json( undef ),
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
                'input[0].config' => '60',
                'input[1].name' => 'location',
                'input[1].type' => 'string',
                'input[1].description' => 'Where to place the bomb',
                'input[1].config' => 'In the center',
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
            rank => 0,
            type => 'number',
            description => 'Time to give crew to survive, in minutes',
            config => encode_json( '60' ),
            value => encode_json( undef ),
        };
        is_deeply $got_inputs[1], {
            plan_id => $plan_id,
            name => 'location',
            rank => 1,
            type => 'string',
            description => 'Where to place the bomb',
            config => encode_json( 'In the center' ),
            value => encode_json( undef ),
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
        ->element_exists_not( '.plans-list > :nth-child(1) [data-last-run-finished]', 'run finished not shown' )
        ->element_exists_not( '.plans-list > :nth-child(1) [data-last-run-started]', 'run started not shown' )
        ->element_exists_not( '.plans-list > :nth-child(1) [data-last-run-state]', 'run state not shown' )

        ->text_like( '.plans-list > :nth-child(2) h2', qr{Clean the ship} )
        ->text_like( '.plans-list > :nth-child(2) .description', qr{Of any remains of the crew} )
        ->element_exists( '.plans-list > :nth-child(2) a.run', 'run button exists' )
        ->attr_is( '.plans-list > :nth-child(2) a.run', href => '/plan/' . $plans[1]{plan_id} . '/run' )
        ->element_exists( '.plans-list > :nth-child(2) a.edit', 'edit button exists' )
        ->attr_is( '.plans-list > :nth-child(2) a.edit', href => '/plan/' . $plans[1]{plan_id} )
        ->element_exists( '.plans-list > :nth-child(2) a.delete', 'delete button exists' )
        ->attr_is( '.plans-list > :nth-child(2) a.delete', href => '/plan/' . $plans[1]{plan_id} . '/delete' )
        ->element_exists_not( '.plans-list > :nth-child(2) [data-last-run-finished]', 'run finished not shown' )
        ->element_exists_not( '.plans-list > :nth-child(2) [data-last-run-started]', 'run started not shown' )
        ->element_exists_not( '.plans-list > :nth-child(2) [data-last-run-state]', 'run state not shown' )

        ->text_like( '.plans-list > :nth-child(3) h2', qr{Find a replacement crew} )
        ->text_like( '.plans-list > :nth-child(3) .description', qr{After their inevitable deaths} )
        ->element_exists( '.plans-list > :nth-child(3) a.run', 'run button exists' )
        ->attr_is( '.plans-list > :nth-child(3) a.run', href => '/plan/' . $plans[2]{plan_id} . '/run' )
        ->element_exists( '.plans-list > :nth-child(3) a.edit', 'edit button exists' )
        ->attr_is( '.plans-list > :nth-child(3) a.edit', href => '/plan/' . $plans[2]{plan_id} )
        ->element_exists( '.plans-list > :nth-child(3) a.delete', 'delete button exists' )
        ->attr_is( '.plans-list > :nth-child(3) a.delete', href => '/plan/' . $plans[2]{plan_id} . '/delete' )
        ->element_exists_not( '.plans-list > :nth-child(3) [data-last-run-finished]', 'run finished not shown' )
        ->element_exists_not( '.plans-list > :nth-child(3) [data-last-run-started]', 'run started not shown' )
        ->element_exists_not( '.plans-list > :nth-child(3) [data-last-run-state]', 'run state not shown' )
        ;

    my @runs;
    subtest 'default plan order by run finished, started, created' => sub {
        # Insert some runs to order plans
        push @runs, (
            # Should be second, since started after above
            $t->app->yancy->create( zapp_runs => {
                $plans[1]->%{qw( name description )},
                plan_id => $plans[1]{plan_id},
                created => '2021-02-01 00:00:00',
                started => '2021-02-01 00:00:00',
                finished => '2021-02-02 00:00:00',
                state => 'failed',
            }),
            # Should be first, since finished last
            $t->app->yancy->create( zapp_runs => {
                $plans[2]->%{qw( name description )},
                plan_id => $plans[2]{plan_id},
                created => '2021-02-03 00:00:00',
                started => '2021-02-04 00:00:00',
                finished => '2021-02-05 00:00:00',
                state => 'killed',
            }),
        );

        $t->get_ok( '/' )->status_is( 200 )
            ->text_like( '.plans-list > :nth-child(3) h2', qr{Deliver a package} )
            ->element_exists_not( '.plans-list > :nth-child(3) [data-last-run-finished]', 'last run finished not showing' )
            ->element_exists_not( '.plans-list > :nth-child(3) [data-last-run-started]', 'last run started not showing' )
            ->element_exists_not( '.plans-list > :nth-child(3) [data-last-run-state]', 'last run state not showing' )

            ->text_like( '.plans-list > :nth-child(2) h2', qr{Clean the ship} )
            ->element_exists( '.plans-list > :nth-child(2) [data-last-run-finished]', 'last run finished showing' )
            ->attr_is(
                '.plans-list > :nth-child(2) [data-last-run-finished]',
                href => '/run/' . $runs[0],
                'last run finished link is correct',
            )
            ->attr_is( '.plans-list > :nth-child(2) time', datetime => '2021-02-02 00:00:00' )
            ->text_is( '.plans-list > :nth-child(2) [data-last-run-state]', 'failed', 'run state shown' )

            ->text_like( '.plans-list > :nth-child(1) h2', qr{Find a replacement crew} )
            ->element_exists( '.plans-list > :nth-child(1) [data-last-run-finished]', 'last run finished showing' )
            ->attr_is(
                '.plans-list > :nth-child(1) [data-last-run-finished]',
                href => '/run/' . $runs[1],
                'last run finished link is correct',
            )
            ->attr_is( '.plans-list > :nth-child(1) time', datetime => '2021-02-05 00:00:00' )
            ->text_is( '.plans-list > :nth-child(1) [data-last-run-state]', 'killed', 'run state shown' )
            ;
    };

    subtest 'running tasks always shown on top' => sub {
        # Insert some runs to order plans
        push @runs, (
            # Should be first now, since it is active
            $t->app->yancy->create( zapp_runs => {
                $plans[0]->%{qw( name description )},
                plan_id => $plans[0]{plan_id},
                created => '2021-02-03 00:00:00',
                started => '2021-02-04 00:00:00',
                state => 'active',
            }),
            # Should be second now, since it is inactive
            $t->app->yancy->create( zapp_runs => {
                $plans[1]->%{qw( name description )},
                plan_id => $plans[1]{plan_id},
                created => '2021-02-03 00:00:00',
                state => 'inactive',
            }),
        );

        $t->get_ok( '/' )->status_is( 200 )
            ->text_like( '.plans-list > :nth-child(1) h2', qr{Deliver a package} )
            ->element_exists( '.plans-list > :nth-child(1) [data-last-run-started]', 'last run started showing' )
            ->attr_is(
                '.plans-list > :nth-child(1) [data-last-run-started]',
                href => '/run/' . $runs[2],
                'last run started link is correct',
            )
            ->attr_is( '.plans-list > :nth-child(1) time', datetime => '2021-02-04 00:00:00' )
            ->text_is( '.plans-list > :nth-child(1) [data-last-run-state]', 'active', 'run state shown' )

            ->text_like( '.plans-list > :nth-child(2) h2', qr{Clean the ship} )
            ->element_exists( '.plans-list > :nth-child(2) [data-last-run-created]', 'last run created showing' )
            ->attr_is(
                '.plans-list > :nth-child(2) [data-last-run-created]',
                href => '/run/' . $runs[3],
                'last run inactive link is correct',
            )
            ->attr_is( '.plans-list > :nth-child(2) time', datetime => '2021-02-03 00:00:00' )
            ->text_is( '.plans-list > :nth-child(2) [data-last-run-state]', 'inactive', 'run state shown' )

            ->text_like( '.plans-list > :nth-child(3) h2', qr{Find a replacement crew} )
            ->element_exists( '.plans-list > :nth-child(3) [data-last-run-finished]', 'last run finished showing' )
            ->attr_is(
                '.plans-list > :nth-child(3) [data-last-run-finished]',
                href => '/run/' . $runs[1],
                'last run finished link is correct',
            )
            ->attr_is( '.plans-list > :nth-child(3) time', datetime => '2021-02-05 00:00:00' )
            ->text_is( '.plans-list > :nth-child(3) [data-last-run-state]', 'killed', 'run state shown' )
            ;
    };

    # XXX: Filter plans by name/description
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
            },
        ],
        inputs => [
            {
                name => 'color',
                type => 'string',
                description => 'What color of scissors',
                value => encode_json( 'White' ),
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

    $t->post_ok( "/plan/$plan_id/delete" )->status_is( 302, 'delete success redirects' )
        ->header_is( Location => '/', 'redirects to plan list' )
        ;
    ok !$t->app->yancy->get( zapp_plans => $plan_id ), 'plan does not exist';
    ok !$t->app->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } ), 'plan tasks deleted'
        or diag explain $t->app->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } );
    ok !$t->app->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } ), 'plan inputs deleted'
        or diag explain $t->app->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } );
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

