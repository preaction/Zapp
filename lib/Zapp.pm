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
    run_id BIGINT REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    minion_job_id BIGINT NOT NULL,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ),
    PRIMARY KEY ( run_id, minion_job_id )
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
    run_id BIGINT REFERENCES zapp_runs ( run_id ) ON DELETE CASCADE,
    minion_job_id BIGINT NOT NULL,
    task_id BIGINT REFERENCES zapp_plan_tasks ( task_id ),
    PRIMARY KEY ( run_id, minion_job_id )
);


