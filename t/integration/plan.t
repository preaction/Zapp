
=head1 DESCRIPTION

This test takes a single plan through an entire lifecycle of create,
run, edit (while running), view run, delete.

=cut

use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Zapp;

my $t = Test::Zapp->new( 'Zapp' );
my ( $plan_id, $run_id );

subtest 'create a new plan' => sub {
    $t->post_ok( '/plan',
        form => {
            name => 'Assassinate Fry the Solid',
            description => 'He must die so Bont may live!',
            'input[0].name' => 'weapon',
            'input[0].type' => 'string',
            'input[0].value' => 'straw',
            'input[1].name' => 'where',
            'input[1].type' => 'string',
            'input[1].value' => 'great hall',
            'input[2].name' => 'who',
            'input[2].type' => 'string',
            'input[2].value' => 'Gorgak',
            'task[0].class' => 'Zapp::Task::Script',
            'task[0].name' => 'Execute',
            'task[0].input.script' => 'echo {{who}} in the {{where}} with the {{weapon}}',
            'task[0].output[0].name' => 'last_exit',
            'task[0].output[0].expr' => 'exit',
        },
    )
        ->status_is( 302 )
        ->header_like( Location => qr{/plan/\d+} )
        ;
    ( $plan_id ) = $t->tx->res->headers->location =~ m{(\d+)};
};

subtest 'start a run' => sub {
    $t->post_ok( "/plan/$plan_id/run",
        form => {
            'input[0].name' => 'weapon',
            'input[0].type' => 'string',
            'input[0].value' => 'Juice-o-matic 4000',
            'input[1].name' => 'where',
            'input[1].type' => 'string',
            'input[1].value' => 'courtyard',
            'input[2].name' => 'who',
            'input[2].type' => 'string',
            'input[2].value' => 'Bont',
        },
    )
        ->status_is( 302 )
        ->header_like( Location => qr{/run/\d+} )
        ;
    ( $run_id ) = $t->tx->res->headers->location =~ m{(\d+)};

    subtest 'can view pending run' => sub {
        $t->get_ok( "/run/$run_id" )->status_is( 200 );
    };
};

subtest 'edit the plan' => sub {
    # Add a task
    $t->post_ok( '/plan',
        form => {
            name => 'Assassinate Fry the Solid',
            description => 'He must die so Bont may live!',
            'input[0].name' => 'weapon',
            'input[0].type' => 'string',
            'input[0].value' => 'straw',
            'input[1].name' => 'where',
            'input[1].type' => 'string',
            'input[1].value' => 'great hall',
            'input[2].name' => 'who',
            'input[2].type' => 'string',
            'input[2].value' => 'Gorgak',
            'task[0].class' => 'Zapp::Task::Script',
            'task[0].name' => 'Execute',
            'task[0].input.script' => 'echo {{who}} in the {{where}} with the {{weapon}}',
            'task[0].output[0].name' => 'last_exit',
            'task[0].output[0].expr' => 'exit',
            'task[1].class' => 'Zapp::Task::Script',
            'task[1].name' => 'Coronate Bont',
            'task[1].input.script' => 'echo I, Bont, who ate Fry the Solid...',
        },
    )
        ->status_is( 302 )
        ->header_like( Location => qr{/plan/\d+} )
        ;

    # Run is not changed
    my @run_tasks = $t->app->yancy->list( zapp_run_tasks => { run_id => $run_id } );
    is scalar @run_tasks, 1, 'run is not changed when plan is edited';
};

subtest 'perform the run' => sub {
    $t->run_queue;
    subtest 'can view finished run' => sub {
        $t->get_ok( "/run/$run_id" )->status_is( 200 );
    };
};

subtest 'delete the plan' => sub {
    $t->post_ok( "/plan/$plan_id/delete" )->status_is( 302 )
        ->header_is( Location => '/' )
        ;
    subtest 'can view run without plan' => sub {
        $t->get_ok( "/run/$run_id" )->status_is( 200 );
    };
};

done_testing;
