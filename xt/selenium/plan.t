
=head1 DESCRIPTION

To run this test, you must install Test::Mojo::Role::Selenium and
Selenium::Chrome. Then you must set the C<TEST_SELENIUM> environment
variable to C<1>.

Additionally, setting C<TEST_SELENIUM_CAPTURE=1> in the environment
will add screenshots to the C<t/selenium> directory. Each screenshot
begins with a counter so you can see the application state as the test
runs.

=cut

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Mojo::JSON qw( encode_json decode_json );

BEGIN {
    eval "use Test::Mojo::Role::Selenium 0.16; 1"
        or plan skip_all => 'Test::Mojo::Role::Selenium >= 0.16 required to run this test';
};

use Test::mysqld;
my $mysqld = Test::mysqld->new or plan skip_all => $Test::mysqld::errstr;

$ENV{MOJO_SELENIUM_DRIVER} ||= 'Selenium::Chrome';
$ENV{TEST_SELENIUM_CAPTURE} ||= 0; # Disable screenshots by default

my $t = Test::Mojo->with_roles('+Selenium')->new( 'Zapp', {
    backend => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
    minion => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
} );
$t->setup_or_skip_all;

subtest 'create a plan' => sub {
    $t->navigate_ok( '/plan' )
        ->status_is( 200 )
        ;

    # Plan information
    $t->wait_for( 'input[name=name]' )
      ->send_keys_ok( 'input[name=name]', 'Capture the Feministas' )
      ->send_keys_ok( '[name=description]', 'Stop the femolution!' )
      ;

    # Add a Request
    $t->click_ok( 'select.add-task' )
      ->click_ok( 'select.add-task option[value="Zapp::Task::Request"]' )
      ->wait_for( '[name="task[0].name"]' )

      ->live_element_exists(
          '[name="task[0].args.method"] option[selected][value=GET]',
          'GET is selected by default',
        )

      ->send_keys_ok( '[name="task[0].name"]', 'Find the honeybun hideout' )
      ->send_keys_ok( '[name="task[0].description"]', 'Somewhere on Mars...' )
      ->click_ok( '[name="task[0].args.method"]' )
      ->click_ok( '[name="task[0].args.method"] option[value=GET]' )
      ->send_keys_ok( '[name="task[0].args.url"]', 'http://example.com' )
      ;

    # Add a test
    $t->click_ok( '#all-tasks > :nth-child(1) .tests-tab' )
      ->wait_for( '#all-tasks > :nth-child(1) .all-tests.active' )
      ->click_ok( '#all-tasks > :nth-child(1) button.test-add' )
      ->wait_for( '[name="task[0].tests[0].expr"]' )
      ->send_keys_ok( '[name="task[0].tests[0].expr"]', 'frequency' )
      ->click_ok( '[name="task[0].tests[0].op"]' )
      ->click_ok( '[name="task[0].tests[0].op"] option[value="=="]' )
      ->send_keys_ok( '[name="task[0].tests[0].value"]', '1138' )
      ;

    # Add a Request
    $t->click_ok( 'select.add-task' )
      ->click_ok( 'select.add-task option[value="Zapp::Task::Request"]' )
      ->wait_for( '[name="task[1].name"]' )

      ->send_keys_ok( '[name="task[1].name"]', 'Open a hailing channel' )
      ->send_keys_ok( '[name="task[1].description"]', 'For my victory yodel' )
      ->send_keys_ok( '[name="task[1].args.url"]', 'http://example.com' )
      ;

    # Add a test
    $t->click_ok( '#all-tasks > :nth-child(2) .tests-tab' )
      ->wait_for( '#all-tasks > :nth-child(2) .all-tests.active' )
      ->click_ok( '#all-tasks > :nth-child(2) button.test-add' )
      ->wait_for( '[name="task[1].tests[0].expr"]' )
      ->send_keys_ok( '[name="task[1].tests[0].expr"]', 'frequency' )
      ->click_ok( '[name="task[1].tests[0].op"]' )
      ->click_ok( '[name="task[1].tests[0].op"] option[value="=="]' )
      ->send_keys_ok( '[name="task[1].tests[0].value"]', '1138' )
      ;

    $t->click_ok( '#all-tasks > :nth-child(2) button.test-add' )
      ->wait_for( '[name="task[1].tests[1].expr"]' )
      ->send_keys_ok( '[name="task[1].tests[1].expr"]', 'volume' )
      ->click_ok( '[name="task[1].tests[1].op"]' )
      ->click_ok( '[name="task[1].tests[1].op"] option[value=">"]' )
      ->send_keys_ok( '[name="task[1].tests[1].value"]', 'loud' )
      ;

    # Save the plan
    $t->click_ok( '[name=save-plan]' )
        ->wait_until( sub { $_->get_current_url =~ m{plan/(\d+)} } )
        ;

    # Verify plan saved
    my ( $plan_id ) = $t->driver->get_current_url =~ m{plan/(\d+)};

    my $got_plan = $t->app->yancy->get( zapp_plans => $plan_id );
    ok $got_plan, 'found plan';
    is $got_plan->{name}, 'Capture the Feministas', 'plan name correct';
    is $got_plan->{description}, 'Stop the femolution!', 'plan description correct';

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
            output => decode_json( $got_tasks[0]{output} ),
        },
        {
            plan_id => $got_plan->{plan_id},
            task_id => $got_tasks[0]{task_id},
            class =>'Zapp::Task::Request',
            name => 'Find the honeybun hideout',
            description => 'Somewhere on Mars...',
            args => {
                method => 'GET',
                url => 'http://example.com',
                body => '',
                content_type => '',
                auth => {
                    type => '',
                    token => '',
                },
            },
            output => [],
        },
        'task 1 is correct';
    is_deeply
        {
            $got_tasks[1]->%*,
            args => decode_json( $got_tasks[1]{args} ),
            output => decode_json( $got_tasks[1]{output} ),
        },
        {
            plan_id => $got_plan->{plan_id},
            task_id => $got_tasks[1]{task_id},
            class =>'Zapp::Task::Request',
            name => 'Open a hailing channel',
            description => 'For my victory yodel',
            args => {
                method => 'GET',
                url => 'http://example.com',
                body => '',
                content_type => '',
                auth => {
                    type => '',
                    token => '',
                },
            },
            output => [],
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

    my @got_tests = $t->app->yancy->list(
        zapp_plan_tests => {
            plan_id => $plan_id,
        },
        {
            order_by => [ qw( test_id task_id ) ],
        },
    );
    is scalar @got_tests, 3, 'got 3 tests for plan';
    is_deeply $got_tests[0],
        {
            test_id => $got_tests[0]{test_id},
            plan_id => $plan_id,
            task_id => $got_tasks[0]{task_id},
            expr => 'frequency',
            op => '==',
            value => '1138',
        },
        'task 1 test 1 is correct';
    is_deeply $got_tests[1],
        {
            test_id => $got_tests[1]{test_id},
            plan_id => $plan_id,
            task_id => $got_tasks[1]{task_id},
            expr => 'frequency',
            op => '==',
            value => '1138',
        },
        'task 2 test 1 is correct';
    is_deeply $got_tests[2],
        {
            test_id => $got_tests[2]{test_id},
            plan_id => $plan_id,
            task_id => $got_tasks[1]{task_id},
            expr => 'volume',
            op => '>',
            value => 'loud',
        },
        'task 2 test 2 is correct';

};

subtest 'edit a plan' => sub {
    my $plan_id = $t->app->yancy->create( zapp_plans => {
        name => 'Blow up Garbage Ball',
        description => 'Save New New York from certain, smelly doom.',
    } );

    my @task_ids = (
        $t->app->yancy->create( zapp_plan_tasks => {
            plan_id => $plan_id,
            name => 'Deploy the Bomb',
            description => 'Deploy the bomb between the Bart Simpson dolls.',
            class => 'Zapp::Task::Script',
            args => encode_json({
                script => "liftoff;\ndrop the_bomb\n",
            }),
        } ),

        $t->app->yancy->create( zapp_plan_tasks => {
            plan_id => $plan_id,
            name => 'Verify bomb placement',
            description => q{Let's blow it up already!},
            class => 'Zapp::Task::Script',
            args => encode_json({
                script => 'make check',
            }),
        } ),
    );

    my @test_ids = (
        $t->app->yancy->create( zapp_plan_tests => {
            plan_id => $plan_id,
            task_id => $task_ids[0],
            expr => 'exit',
            op => '==',
            value => '0',
        } ),
        $t->app->yancy->create( zapp_plan_tests => {
            plan_id => $plan_id,
            task_id => $task_ids[1],
            expr => 'bomb.timer',
            op => '==',
            value => '25:00',
        } ),
        $t->app->yancy->create( zapp_plan_tests => {
            plan_id => $plan_id,
            task_id => $task_ids[1],
            expr => 'bomb.rotation',
            op => '==',
            value => '180',
        } ),
    );

    $t->app->yancy->create( zapp_task_parents => {
        task_id => $task_ids[1],
        parent_task_id => $task_ids[0],
    });

    $t->navigate_ok( '/plan/' . $plan_id )
        ->status_is( 200 )
        ;

    # Existing form is filled out
    $t->wait_for( 'input[name=name]' )
        ->live_value_is( '[name=name]', 'Blow up Garbage Ball' )
        ->live_value_is( '[name=description]', 'Save New New York from certain, smelly doom.' )
        ->live_value_is( '[name="task[0].class"]', 'Zapp::Task::Script' )
        ->live_value_is( '[name="task[0].task_id"]', $task_ids[0] )
        ->live_value_is( '[name="task[0].name"]', 'Deploy the Bomb' )
        ->live_value_is( '[name="task[0].description"]', 'Deploy the bomb between the Bart Simpson dolls.' )
        ->live_value_is( '[name="task[0].args.script"]', "liftoff;\ndrop the_bomb\n" )
        ->live_value_is( '[name="task[0].tests[0].test_id"]', $test_ids[0] )
        ->live_value_is( '[name="task[0].tests[0].expr"]', 'exit' )
        ->live_value_is( '[name="task[0].tests[0].op"]', '==' )
        ->live_value_is( '[name="task[0].tests[0].value"]', '0' )
        ->live_value_is( '[name="task[1].class"]', 'Zapp::Task::Script' )
        ->live_value_is( '[name="task[1].task_id"]', $task_ids[1] )
        ->live_value_is( '[name="task[1].name"]', 'Verify bomb placement' )
        ->live_value_is( '[name="task[1].description"]', q{Let's blow it up already!} )
        ->live_value_is( '[name="task[1].tests[0].test_id"]', $test_ids[1] )
        ->live_value_is( '[name="task[1].tests[0].expr"]', 'bomb.timer' )
        ->live_value_is( '[name="task[1].tests[0].op"]', '==' )
        ->live_value_is( '[name="task[1].tests[0].value"]', '25:00' )
        ->live_value_is( '[name="task[1].tests[1].test_id"]', $test_ids[2] )
        ->live_value_is( '[name="task[1].tests[1].expr"]', 'bomb.rotation' )
        ->live_value_is( '[name="task[1].tests[1].op"]', '==' )
        ->live_value_is( '[name="task[1].tests[1].value"]', '180' )
        ;

    # Update existing task information
    $t->main::clear_ok( '[name=name]' )
        ->send_keys_ok( '[name=name]', 'Save NNY' )
        ->main::clear_ok( '[name=description]' )
        ->send_keys_ok( '[name=description]', 'Save New New York City' )
        ->main::clear_ok( '[name="task[0].name"]' )
        ->send_keys_ok( '[name="task[0].name"]', 'Build' )
        ->main::clear_ok( '[name="task[0].description"]' )
        ->send_keys_ok( '[name="task[0].description"]', 'Build a bomb' )
        ->main::clear_ok( '[name="task[0].args.script"]' )
        ->send_keys_ok( '[name="task[0].args.script"]', 'make thebomb' )
        ->main::clear_ok( '[name="task[1].name"]' )
        ->send_keys_ok( '[name="task[1].name"]', 'Verify Bomb' )
        ->main::clear_ok( '[name="task[1].description"]' )
        ->send_keys_ok( '[name="task[1].description"]', 'Make sure this time' )
        ->click_ok( '#all-tasks > :nth-child(2) .tests-tab' )
        ->wait_for( '#all-tasks > :nth-child(2) .all-tests.active' )
        ->main::clear_ok( '[name="task[1].tests[0].expr"]' )
        ->send_keys_ok( '[name="task[1].tests[0].expr"]', 'bomb.orientation' )
        ->click_ok( '[name="task[1].tests[0].op"]' )
        ->click_ok( '[name="task[1].tests[0].op"] option[value="!="]' )
        ->main::clear_ok( '[name="task[1].tests[0].value"]' )
        ->send_keys_ok( '[name="task[1].tests[0].value"]', 'reverse' )
        ;

    # Add a new test
    $t->click_ok( '#all-tasks > :nth-child(1) .tests-tab' )
        ->wait_for( '#all-tasks > :nth-child(1) .all-tests.active' )
        ->click_ok( '#all-tasks > :nth-child(1) button.test-add' )
        ->wait_for( '[name="task[0].tests[1].expr"]' )
        ->send_keys_ok( '[name="task[0].tests[1].expr"]', 'bomb.timer' )
        ->click_ok( '[name="task[0].tests[1].op"]' )
        ->click_ok( '[name="task[0].tests[1].op"] option[value="=="]' )
        ->send_keys_ok( '[name="task[0].tests[1].value"]', '25:00' )
        ;

    # Remove the new test
    $t->click_ok( '#all-tasks > :nth-child(1) .all-tests > ul > :nth-child(2) button.test-remove' )
        ;

    # XXX: Insert a new task in the middle

    # Save
    $t->click_ok( '[name=save-plan]' )
        ;

    subtest 'plan saved correctly' => sub {
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
                output => decode_json( $got_tasks[0]{output} ),
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
                output => [],
            },
            'task 1 is correct';
        is_deeply
            {
                $got_tasks[1]->%*,
                args => decode_json( $got_tasks[1]{args} ),
                output => decode_json( $got_tasks[0]{output} ),
            },
            {
                plan_id => $plan_id,
                class => 'Zapp::Task::Script',
                task_id => $task_ids[1],
                name => 'Verify Bomb',
                description => 'Make sure this time',
                args => {
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
        is scalar @got_tests, 3, 'got 3 tests for plan';
        is_deeply $got_tests[0],
            {
                plan_id => $plan_id,
                task_id => $got_tasks[0]{task_id},
                test_id => $got_tests[0]{test_id},
                expr => 'exit',
                op => '==',
                value => '0',
            },
            'task 1 test 1 is correct';
        is_deeply $got_tests[1],
            {
                plan_id => $plan_id,
                task_id => $got_tasks[1]{task_id},
                test_id => $got_tests[1]{test_id},
                expr => 'bomb.orientation',
                op => '!=',
                value => 'reverse',
            },
            'task 2 test 1 is correct';
        is_deeply $got_tests[2],
            {
                plan_id => $plan_id,
                task_id => $got_tasks[1]{task_id},
                test_id => $got_tests[2]{test_id},
                expr => 'bomb.rotation',
                op => '==',
                value => '180',
            },
            'task 2 test 2 is correct';

    };

    # XXX: Remove a task from the middle
    # XXX: Save

};


done_testing;


sub clear_ok {
    my ( $t, $sel, $desc ) = @_;
    $desc ||= 'cleared ' . $sel;
    $t->tap(
        sub {
            my $elem = eval { $t->driver->find_element( $sel, 'css' ) };
            $t->test( ok => $elem, 'found element for css: ' . $sel );
            $elem->clear();
            $t->test( pass => $desc );
        }
    );
}



