package Zapp;
our $VERSION = '0.001';
# ABSTRACT: Write a sentence about what it does

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 SEE ALSO

L<Minion>, L<Mojolicious::Plugin::Minion::Admin>

=cut

use v5.28;
use Mojo::Base 'Mojolicious', -signatures;
use Scalar::Util qw( blessed );
use Yancy::Util qw( load_backend );
use Mojo::JSON qw( encode_json decode_json );
use Mojo::Loader qw( find_modules load_class );

sub startup( $self ) {

    # XXX: Allow configurable backends, like Minion
    $self->plugin( Config => { default => {
        backend => 'sqlite:zapp.db',
        minion => { SQLite => 'sqlite:zapp.db' },
    } } );

    # XXX: Add migrate() method to Yancy app base class, varying by
    # backend type. Should try to read migrations from each class in
    # $self->isa
    # XXX: Create this migrate() method in a role so it can also be used
    # by Yancy::Plugins or other plugins
    my $backend = load_backend( $self->config->{backend} );
    my ( $db_type ) = blessed( $backend ) =~ m/([^:]+)$/;
    $backend->mojodb->migrations
        ->name( 'zapp' )
        ->from_data( __PACKAGE__, 'migrations.' . lc $db_type . '.sql' )
        ->migrate;

    $self->plugin( Minion => $self->config->{ minion }->%* );

    # XXX: Allow additional task namespaces
    for my $class ( find_modules 'Zapp::Task' ) {
        next if $class eq 'Zapp::Task';
        if ( my $e = load_class( $class ) ) {
            $self->log->error( sprintf "Could not load task class %s: %s", $class, $e );
            next;
        }
        ; say "Adding task class: $class";
        $self->minion->add_task( $class, $class );
    }

    $self->plugin( Yancy =>
        $self->config->%{qw( backend )},
        schema => {
            zapp_plan_inputs => {
                # XXX: Fix read_schema to detect compound primary keys
                'x-id-field' => [qw( plan_id name )],
            },
        },
    );

    # Create/edit plans
    # XXX: Make Yancy support this basic CRUD with relationships?
    # XXX: Otherwise, add custom JSON API
    $self->routes->get( '/plan/:plan_id', { plan_id => undef } )
        ->to( 'plan#edit_plan' )->name( 'zapp.edit_plan' );
    $self->routes->post( '/plan/:plan_id', { plan_id => undef } )
        ->to( 'plan#save_plan' )->name( 'zapp.save_plan' );

    # Create/view runs
    $self->routes->get( '/' )
        ->to( 'plan#list_plans' )->name( 'zapp.list_plans' );
    $self->routes->get( '/plan/:plan_id/run/:run_id', { run_id => undef } )
        ->to( 'plan#edit_run' )->name( 'zapp.edit_run' );
    $self->routes->post( '/plan/:plan_id/run/:run_id', { run_id => undef } )
        ->to( 'plan#save_run' )->name( 'zapp.save_run' );
    $self->routes->get( '/plan/:plan_id/run/:run_id' )
        ->to( 'plan#get_run' )->name( 'zapp.get_run' );

}

=method create_plan

Create a new plan and all related data.

=cut

# XXX: Make Yancy automatically handle relationships like this
sub create_plan( $self, $plan ) {
    my @inputs = @{ delete $plan->{inputs} // [] };
    my @tasks = @{ delete $plan->{tasks} // [] };
    my $plan_id = $self->yancy->create( zapp_plans => $plan );

    for my $input ( @inputs ) {
        $input->{plan_id} = $plan_id;
        $self->yancy->create( zapp_plan_inputs => $input );
    }

    my $prev_task_id;
    for my $task ( @tasks ) {
        $task->{plan_id} = $plan_id;
        my $tests = $task->{tests} ? delete $task->{tests} : [];
        my $task_id = $self->yancy->create( zapp_plan_tasks => $task );
        if ( $prev_task_id ) {
            $self->yancy->create( zapp_task_parents => {
                task_id => $task_id,
                parent_task_id => $prev_task_id,
            });
        }
        if ( $tests && @$tests ) {
            for my $test ( @$tests ) {
                $test->{ task_id } = $task_id;
                $test->{ plan_id } = $plan_id;
                $test->{ test_id } = $self->yancy->create( zapp_plan_tests => $test );
            }
        }
        $prev_task_id = $task_id;
        $task->{ task_id } = $task_id;
        $task->{ tests } = $tests;
    }

    $plan->{plan_id} = $plan_id;
    $plan->{tasks} = \@tasks;

    return $plan;
}

=method enqueue

Enqueue a plan.

=cut

sub enqueue( $self, $plan_id, $input, %opt ) {
    $opt{queue} ||= 'zapp';

    my $run = {
        plan_id => $plan_id,
        # XXX: Auto-encode/-decode JSON fields in Yancy schema
        input_values => encode_json( $input ),
    };

    my $run_id = $run->{run_id} = $self->yancy->create( zapp_runs => $run );

    # Create Minion jobs for this run
    my @tasks = $self->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } );
    my %task_parents;
    for my $task_id ( map $_->{task_id}, @tasks ) {
        my @parents = $self->yancy->list( zapp_task_parents => { task_id => $task_id } );
        $task_parents{ $task_id } = [ map $_->{parent_task_id}, @parents ];
    }

    my %task_jobs;
    # Loop over tasks, making the job if the task's parents are made.
    # Stop the loop once all tasks have jobs.
    my $loops = @tasks * @tasks;
    while ( @tasks != keys %task_jobs ) {
        # Loop over any tasks that aren't made yet
        for my $task ( grep !$task_jobs{ $_->{task_id} }, @tasks ) {
            my $task_id = $task->{task_id};
            # Skip if we haven't created all parents
            next if $task_parents{ $task_id } && grep { !$task_jobs{ $_ } } $task_parents{ $task_id }->@*;

            # XXX: Expose more Minion job configuration
            my %job_opts;
            if ( my @parents = $task_parents{ $task_id } ) {
                $job_opts{ parents } = [ map $task_jobs{ $_ }, @parents ];
            }

            my $args = decode_json( $task->{args} );
            if ( ref $args ne 'ARRAY' ) {
                $args = [ $args ];
            }

            $self->log->debug( sprintf 'Enqueuing task %s', $task->{class} );
            my $job_id = $self->minion->enqueue(
                $task->{class} => $args,
                \%job_opts,
            );
            $task_jobs{ $task_id } = $job_id;

            push $run->{jobs}->@*,
                $self->yancy->create( zapp_run_jobs => {
                    run_id => $run_id,
                    task_id => $task_id,
                    minion_job_id => $job_id,
                } );
        }
        last if !$loops--;
    }
    if ( @tasks != keys %task_jobs ) {
        $self->log->error( 'Could not create jobs: Infinite loop' );
        return undef;
    }

    return $run;
}

1;
__DATA__
@@ migrations.mysql.sql

-- 1 up
CREATE TABLE zapp_plans (
    plan_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT
);

CREATE TABLE zapp_plan_tasks (
    task_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    class VARCHAR(255) NOT NULL,
    args JSON
);

CREATE TABLE zapp_task_parents (
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    parent_task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE RESTRICT,
    PRIMARY KEY ( task_id, parent_task_id )
);

CREATE TABLE zapp_plan_inputs (
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type ENUM( 'string', 'number', 'integer', 'boolean' ) NOT NULL,
    description TEXT,
    default_value JSON,
    PRIMARY KEY ( plan_id, name )
);

CREATE TABLE zapp_runs (
    run_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ),
    description TEXT,
    input_values JSON
);

CREATE TABLE zapp_run_jobs (
    minion_job_id BIGINT NOT NULL,
    run_id BIGINT REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ),
    PRIMARY KEY ( minion_job_id )
);

CREATE TABLE zapp_plan_tests (
    test_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    expr VARCHAR(255) NOT NULL,
    op VARCHAR(255) NOT NULL,
    value VARCHAR(255) NOT NULL
);

@@ migrations.sqlite.sql

-- 1 up
CREATE TABLE zapp_plans (
    plan_id INTEGER PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT
);

CREATE TABLE zapp_plan_tasks (
    task_id INTEGER PRIMARY KEY,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    class VARCHAR(255) NOT NULL,
    args JSON
);

CREATE TABLE zapp_task_parents (
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    parent_task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE RESTRICT,
    PRIMARY KEY ( task_id, parent_task_id )
);

CREATE TABLE zapp_plan_inputs (
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    -- SQLite lacks ENUM, but we can fake it in a way Yancy can parse
    type VARCHAR(7) NOT NULL CHECK(type IN ('string', 'number', 'integer', 'boolean')),
    description TEXT,
    default_value JSON,
    PRIMARY KEY ( plan_id, name )
);

CREATE TABLE zapp_runs (
    run_id INTEGER PRIMARY KEY,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ),
    description TEXT,
    input_values JSON
);

CREATE TABLE zapp_run_jobs (
    minion_job_id BIGINT NOT NULL,
    run_id BIGINT REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ),
    PRIMARY KEY ( minion_job_id )
);

CREATE TABLE zapp_plan_tests (
    test_id BIGINT AUTOINCREMENT PRIMARY KEY,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    expr VARCHAR(255) NOT NULL,
    op VARCHAR(255) NOT NULL,
    value VARCHAR(255) NOT NULL
);


