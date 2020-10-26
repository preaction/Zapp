
=head1 DESCRIPTION

This tests Zapp::Controller::Plan (except for the JavaScript involved).

=cut

use Mojo::Base -strict, -signatures;
use Test::Mojo;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json );

my $mysqld = Test::mysqld->new or plan skip_all => $Test::mysqld::errstr;

my $t = Test::Mojo->new( 'Zapp', {
    backend => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
} );

subtest 'create new plan' => sub {

    subtest 'new plan form' => sub {
        $t->get_ok( '/plan' )->status_is( 200 )
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
                'Request',
                'second task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(3)',
                value => 'Zapp::Task::Request',
                'second task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(4)',
                'Script',
                'third task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(4)',
                value => 'Zapp::Task::Script',
                'third task option value is correct',
            )
            ;

    };

    subtest 'save plan' => sub {
        $t->post_ok( "/plan",
            form => {
                name => 'The Mighty One',
                description => 'Save the mighty one, save the universe.',
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
            zapp_tasks => {
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
            parent_id => $got_tasks[0]{task_id},
        };

    };

};

subtest 'edit existing plan' => sub {

    my $plan_id = $t->app->yancy->create( zapp_plans => {
        name => 'Blow up Garbage Ball',
        description => 'Save New New York from certain, smelly doom.',
    } );

    my @task_ids = (
        $t->app->yancy->create( zapp_tasks => {
            plan_id => $plan_id,
            name => 'Deploy the Bomb',
            description => 'Deploy the bomb between the Bart Simpson dolls.',
            class => 'Zapp::Task::Script',
            args => encode_json({
                script => "liftoff;\ndrop the_bomb\n",
            }),
        } ),

        $t->app->yancy->create( zapp_tasks => {
            plan_id => $plan_id,
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
        } ),
    );

    $t->app->yancy->create( zapp_task_parents => {
        task_id => $task_ids[1],
        parent_id => $task_ids[0],
    });

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
                'Request',
                'second task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(3)',
                value => 'Zapp::Task::Request',
                'second task option value is correct',
            )
            ->text_is(
                'select.add-task option:nth-child(4)',
                'Script',
                'third task option text is correct',
            )
            ->attr_is(
                'select.add-task option:nth-child(4)',
                value => 'Zapp::Task::Script',
                'third task option value is correct',
            )
            ;

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
            zapp_tasks => {
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
            parent_id => $task_ids[0],
        };
    };

};

done_testing;
