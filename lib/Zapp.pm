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
        #; say "Adding task class: $class";
        $self->minion->add_task( $class, $class );
    }

    $self->plugin( Yancy =>
        $self->config->%{qw( backend )},
        schema => {
            zapp_plan_inputs => {
                # XXX: Fix read_schema to detect compound primary keys
                'x-id-field' => [qw( plan_id name )],
            },
            zapp_run_inputs => {
                # XXX: Fix read_schema to detect compound primary keys
                'x-id-field' => [qw( run_id name )],
            },
        },
    );

    # Add basic types
    my %base_types = (
        string => 'Zapp::Type::Text',
        number => 'Zapp::Type::Text',
        integer => 'Zapp::Type::Text',
        boolean => 'Zapp::Type::Text',
        file => 'Zapp::Type::File',
    );
    $self->helper( 'zapp.types' => sub( $c ) { state %types; \%types } );
    $self->helper( 'zapp.add_type' => sub( $c, $name, $type ) {
        my $obj = blessed( $type ) ? $type : undef;
        if ( !defined $obj ) {
            if ( my $e = load_class( $type ) ) {
                die "Could not load type class $type: $e\n";
            }
            $obj = $type->new( app => $c->app );
        }
        else {
            $obj->app( $c->app );
        }
        $c->zapp->types->{ $name } = $obj;
    });
    for my $type_name ( keys %base_types ) {
        $self->zapp->add_type( $type_name, $base_types{ $type_name } );
    }

    # XXX: Add config file for adding types

    # Create/edit plans
    # XXX: Make Yancy support this basic CRUD with relationships?
    # XXX: Otherwise, add custom JSON API
    $self->routes->get( '/plan/:plan_id', { plan_id => undef } )
        ->to( 'plan#edit_plan' )->name( 'zapp.edit_plan' );
    $self->routes->post( '/plan/:plan_id', { plan_id => undef } )
        ->to( 'plan#save_plan' )->name( 'zapp.save_plan' );
    $self->routes->get( '/plan/:plan_id/delete' )
        ->to( 'plan#delete_plan' )->name( 'zapp.delete_plan' );
    $self->routes->post( '/plan/:plan_id/delete' )
        ->to( 'plan#delete_plan' )->name( 'zapp.delete_plan_confirm' );

    # Create/view runs
    $self->routes->get( '/' )
        ->to( 'plan#list_plans' )->name( 'zapp.list_plans' );
    $self->routes->get( '/plan/:plan_id/run', { run_id => undef } )
        ->to( 'plan#edit_run' )->name( 'zapp.new_run' );
    $self->routes->post( '/plan/:plan_id/run', { run_id => undef } )
        ->to( 'plan#save_run' )->name( 'zapp.create_run' );
    $self->routes->get( '/run/:run_id' )
        ->to( 'plan#get_run' )->name( 'zapp.get_run' );
    $self->routes->get( '/run/:run_id/task/:task_id' )
        ->to( 'plan#get_run_task' )->name( 'zapp.get_run_task' );
    # $self->routes->get( '/run/:run_id/edit' )
    # ->to( 'plan#edit_run' )->name( 'zapp.edit_run' );
    # $self->routes->post( '/run/:run_id/edit' )
    # ->to( 'plan#save_run' )->name( 'zapp.save_run' );
    $self->routes->get( '/run/:run_id/stop' )
        ->to( 'plan#stop_run' )->name( 'zapp.stop_run' );
    $self->routes->post( '/run/:run_id/stop' )
        ->to( 'plan#stop_run' )->name( 'zapp.stop_run_confirm' );
    $self->routes->post( '/run/:run_id/start' )
        ->to( 'plan#start_run' )->name( 'zapp.start_run_confirm' );
    $self->routes->get( '/run/:run_id/kill' )
        ->to( 'plan#kill_run' )->name( 'zapp.kill_run' );
    $self->routes->post( '/run/:run_id/kill' )
        ->to( 'plan#kill_run' )->name( 'zapp.kill_run_confirm' );

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
            $self->yancy->create( zapp_plan_task_parents => {
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

sub enqueue( $self, $plan_id, $input={}, %opt ) {
    $opt{queue} ||= 'zapp';

    # Create the run in the database by copying the plan
    my $plan = $self->yancy->get( zapp_plans => $plan_id );
    delete $plan->{created};
    my $run = {
        %$plan,
        # XXX: Auto-encode/-decode JSON fields in Yancy schema
        input_values => encode_json( $input ),
    };
    my $run_id = $run->{run_id} = $self->yancy->create( zapp_runs => $run );

    my %task_id_map; # plan task_id -> run task_id
    my @tasks = $self->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } );
    for my $task ( @tasks ) {
        delete $task->{plan_id};
        $task->{run_id} = $run_id;
        $task->{plan_task_id} = delete $task->{task_id};
        my $task_id = $task->{task_id} = $self->yancy->create( zapp_run_tasks => $task );
        ; $self->log->debug( "Creating run task: " . $self->dumper( $task ) );
        $task_id_map{ $task->{plan_task_id} } = $task->{task_id};
        # Copy tests for the run
        my @tests = $self->yancy->list( zapp_plan_tests => { task_id => $task->{plan_task_id} }, { order_by => 'test_id' } );
        for my $test ( @tests ) {
            $self->yancy->create( zapp_run_tests => {
                $task->%{qw( run_id task_id )},
                run_id => $run_id,
                $test->%{qw( expr op value )},
            } );
        }
        $task->{tests} = \@tests;
    }
    $run->{tasks} = \@tasks;

    # Calculate the parent/child relationships
    my %task_parents;
    for my $plan_task_id ( map $_->{plan_task_id}, @tasks ) {
        my @parents = $self->yancy->list( zapp_plan_task_parents => { task_id => $plan_task_id } );
        next unless @parents;
        for my $parent ( @parents ) {
            $parent->{task_id} = $task_id_map{ $parent->{task_id} };
            $parent->{parent_task_id} = $task_id_map{ $parent->{parent_task_id} };
            $self->yancy->create( zapp_run_task_parents => $parent );
            push $task_parents{ $parent->{task_id} }->@*, $parent->{parent_task_id};
        }
    }
    for my $task ( @tasks ) {
        $task->{parents} = $task_parents{ $task->{task_id} };
    }

    my $jobs = $self->enqueue_tasks( $input, @tasks );
    for my $i ( 0..$#$jobs ) {
        my $job = $jobs->[$i];

        my ( $task ) = grep { $_->{task_id} eq $job->{task_id} } $run->{tasks}->@*;
        $task->{$_} = $job->{$_} for keys %$job;

        $self->yancy->backend->set( zapp_run_tasks => $job->{task_id}, $job );
    }

    return $run;
}

sub enqueue_tasks( $self, $input, @tasks ) {
    my @jobs;
    # Create Minion jobs for this run
    my %task_jobs;
    # Loop over tasks, making the job if the task's parents are made.
    # Stop the loop once all tasks have jobs.
    my $loops = @tasks * @tasks;
    while ( @tasks != keys %task_jobs ) {
        # Loop over any tasks that aren't made yet
        for my $task ( grep !$task_jobs{ $_->{task_id} }, @tasks ) {
            my $task_id = $task->{task_id};
            # Skip if we haven't created all parents
            next if @{ $task->{parents} // [] } && grep { !$task_jobs{ $_ } } $task->{parents}->@*;

            # XXX: Expose more Minion job configuration
            my %job_opts;
            if ( my @parents = @{ $task->{parents} // [] } ) {
                $job_opts{ parents } = [
                    map $task_jobs{ $_ }, @parents
                ];
            }

            my $args = decode_json( $task->{input} );
            if ( ref $args ne 'ARRAY' ) {
                $args = [ $args ];
            }

            $self->log->debug( sprintf 'Enqueuing task %s', $task->{class} );
            my $job_id = $self->minion->enqueue(
                $task->{class} => $args,
                \%job_opts,
            );
            $task_jobs{ $task_id } = $job_id;

            push @jobs, {
                task_id => $task_id,
                job_id => $job_id,
                # All jobs with no parents must have the initial context. Other jobs
                # will get their context filled in by their parent.
                context => encode_json(
                    !$job_opts{parents} ? $input : {},
                ),
            };
        }
        last if !$loops--;
    }
    if ( @tasks != keys %task_jobs ) {
        $self->log->error( 'Could not create jobs: Infinite loop' );
        return undef;
    }

    return \@jobs;
}

1;
__DATA__
@@ migrations.mysql.sql

-- 1 up
CREATE TABLE zapp_plans (
    plan_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_plan_tasks (
    task_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    class VARCHAR(255) NOT NULL,
    input JSON,
    output JSON,
    CONSTRAINT FOREIGN KEY ( plan_id ) REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_plan_task_parents (
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    parent_task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE RESTRICT,
    PRIMARY KEY ( task_id, parent_task_id ),
    CONSTRAINT FOREIGN KEY ( task_id ) REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    CONSTRAINT FOREIGN KEY ( parent_task_id ) REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE
);

CREATE TABLE zapp_plan_inputs (
    plan_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    description TEXT,
    value JSON,
    PRIMARY KEY ( plan_id, name ),
    CONSTRAINT FOREIGN KEY ( plan_id ) REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_runs (
    run_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_id BIGINT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    input_values JSON,
    created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started DATETIME NULL,
    finished DATETIME NULL,
    state VARCHAR(20) NOT NULL DEFAULT 'inactive',
    output JSON,
    CONSTRAINT FOREIGN KEY ( plan_id ) REFERENCES zapp_plans ( plan_id ) ON DELETE SET NULL
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_run_tasks (
    task_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id BIGINT NOT NULL,
    plan_task_id BIGINT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    class VARCHAR(255) NOT NULL,
    input JSON,
    output JSON,
    context JSON,
    state VARCHAR(20) NOT NULL DEFAULT 'inactive',
    job_id BIGINT,
    CONSTRAINT FOREIGN KEY ( run_id ) REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    CONSTRAINT FOREIGN KEY ( plan_task_id ) REFERENCES zapp_plan_tasks ( task_id ) ON DELETE SET NULL
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_run_task_parents (
    task_id BIGINT REFERENCES zapp_run_tasks ( task_id ) ON DELETE CASCADE,
    parent_task_id BIGINT REFERENCES zapp_run_tasks ( task_id ) ON DELETE RESTRICT,
    PRIMARY KEY ( task_id, parent_task_id ),
    CONSTRAINT FOREIGN KEY ( task_id ) REFERENCES zapp_run_tasks ( task_id ) ON DELETE CASCADE,
    CONSTRAINT FOREIGN KEY ( parent_task_id ) REFERENCES zapp_run_tasks ( task_id ) ON DELETE CASCADE
);

CREATE TABLE zapp_run_inputs (
    run_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    description TEXT,
    value JSON,
    PRIMARY KEY ( run_id, name ),
    CONSTRAINT FOREIGN KEY ( run_id ) REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_plan_tests (
    test_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    plan_id BIGINT NOT NULL,
    task_id BIGINT NOT NULL,
    expr VARCHAR(255) NOT NULL,
    op VARCHAR(255) NOT NULL,
    value VARCHAR(255) NOT NULL,
    CONSTRAINT FOREIGN KEY ( plan_id ) REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    CONSTRAINT FOREIGN KEY ( task_id ) REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_run_tests (
    test_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id BIGINT NOT NULL,
    task_id BIGINT NOT NULL,
    expr VARCHAR(255) NOT NULL,
    op VARCHAR(255) NOT NULL,
    value VARCHAR(255) NOT NULL,
    expr_value VARCHAR(255) DEFAULT NULL,
    pass BOOLEAN DEFAULT NULL,
    CONSTRAINT FOREIGN KEY ( run_id ) REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    CONSTRAINT FOREIGN KEY ( task_id ) REFERENCES zapp_run_tasks ( task_id ) ON DELETE CASCADE
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE TABLE zapp_run_notes (
    note_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id BIGINT NOT NULL,
    created DATETIME DEFAULT CURRENT_TIMESTAMP,
    event VARCHAR(20) NOT NULL,
    note TEXT NOT NULL,
    CONSTRAINT FOREIGN KEY ( run_id ) REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE
);

@@ migrations.sqlite.sql

-- 1 up
CREATE TABLE zapp_plans (
    plan_id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE zapp_plan_tasks (
    task_id INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    class VARCHAR(255) NOT NULL,
    input JSON,
    output JSON
);

CREATE TABLE zapp_plan_task_parents (
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    parent_task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE RESTRICT,
    PRIMARY KEY ( task_id, parent_task_id )
);

CREATE TABLE zapp_plan_inputs (
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    description TEXT,
    value JSON,
    PRIMARY KEY ( plan_id, name )
);

CREATE TABLE zapp_runs (
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    input_values JSON,
    created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started DATETIME NULL,
    finished DATETIME NULL,
    state VARCHAR(20) NOT NULL DEFAULT 'inactive',
    output JSON
);

CREATE TABLE zapp_run_tasks (
    task_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id BIGINT NOT NULL REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    plan_task_id BIGINT NULL REFERENCES zapp_plan_tasks ( task_id ) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    class VARCHAR(255) NOT NULL,
    input JSON,
    context JSON,
    output JSON,
    state VARCHAR(20) NOT NULL DEFAULT 'inactive',
    job_id BIGINT
);

CREATE TABLE zapp_run_task_parents (
    task_id BIGINT REFERENCES zapp_run_tasks ( task_id ) ON DELETE CASCADE,
    parent_task_id BIGINT REFERENCES zapp_run_tasks ( task_id ) ON DELETE RESTRICT,
    PRIMARY KEY ( task_id, parent_task_id )
);

CREATE TABLE zapp_run_inputs (
    run_id BIGINT REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    description TEXT,
    value JSON,
    PRIMARY KEY ( run_id, name )
);

CREATE TABLE zapp_plan_tests (
    test_id INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_id BIGINT REFERENCES zapp_plans ( plan_id ) ON DELETE CASCADE,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ) ON DELETE CASCADE,
    expr VARCHAR(255) NOT NULL,
    op VARCHAR(255) NOT NULL,
    value VARCHAR(255) NOT NULL
);

CREATE TABLE zapp_run_tests (
    test_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id BIGINT REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    task_id BIGINT REFERENCES zapp_run_tasks ( task_id ) ON DELETE CASCADE,
    expr VARCHAR(255) NOT NULL,
    op VARCHAR(255) NOT NULL,
    value VARCHAR(255) NOT NULL,
    expr_value VARCHAR(255) DEFAULT NULL,
    pass BOOLEAN DEFAULT NULL
);

CREATE TABLE zapp_run_notes (
    note_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id BIGINT NOT NULL REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    created DATETIME DEFAULT CURRENT_TIMESTAMP,
    event VARCHAR(20) NOT NULL,
    note TEXT NOT NULL
);

