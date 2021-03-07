package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;
use List::Util qw( uniq );
use Time::Piece;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Util qw( get_path_from_data get_path_from_schema fill_input );

has zapp_task => sub( $self ) {
    my ( $task ) = $self->app->yancy->list( zapp_run_tasks => { job_id => $self->id } );
    return $task;
};

has zapp_run => sub( $self ) {
    my $task = $self->zapp_task;
    return $self->app->yancy->get( zapp_runs => $task->{run_id} );
};

sub set( $self, %values ) {
    ; say sprintf 'Setting task %s: %s', $self->id, $self->app->dumper( \%values );
    $self->app->yancy->backend->set(
        zapp_run_tasks => $self->zapp_task->{task_id},
        \%values,
    );
    if ( exists $values{state} ) {
        my $run = $self->zapp_run;
        my $run_state = $run->{state};
        if ( $values{state} =~ /(active|failed|stopped|killed)/ && $run->{state} ne $values{state} ) {
            # One job in these states can change the run state
            $run_state = $values{state};
        }
        elsif ( $values{state} =~ /(inactive|finished)/ ) {
            # All tasks must be in this state to change the run state
            my @task_states = uniq map $_->{state}, $self->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} } );
            if ( @task_states == 1 && $task_states[0] eq $values{state} ) {
                $run_state = $values{state};
            }
        }

        if ( $run_state ne $run->{state} ) {
            $self->app->yancy->backend->set(
                zapp_runs => $run->{run_id},
                {
                    state => $run_state,
                    (
                        $run_state eq 'active' ? ( started => Time::Piece->new( $self->info->{started} )->datetime )
                        : $run_state ne 'inactive' ? ( finished => Time::Piece->new( $self->info->{finished} )->datetime )
                        : ()
                    ),
                },
            );
        }
    }
}

sub context( $self ) {
    my $run_job = $self->zapp_task;
    my $context = decode_json( $self->zapp_task->{context} );
    ; $self->app->log->debug( "Got context: " . $self->app->dumper( $context ) );
    for my $name ( keys %$context ) {
        my $input = $context->{ $name };
        my $type = $self->app->zapp->types->{ $input->{type} }
            or die qq{Could not find type "$input->{type}"};
        # XXX: Remove run/task from task_input
        $context->{ $name } = {
            type => $input->{type},
            config => $input->{config},
            value => $type->task_input( $input->{config}, $input->{value} ),
        };
    }
    return $context;
}

sub args( $self, $new_args=undef ) {
    my $args = $new_args || $self->SUPER::args;

    my $context = $self->context;
    my %values;
    for my $key ( keys %$context ) {
        $values{ $key } = $context->{ $key }{value};
    }

    $args = fill_input( \%values, $args );
    $self->SUPER::args( $args );
    return $args;
}

sub execute( $self, @args ) {
    $self->set( state => 'active' );
    return $self->SUPER::execute( @args );
}

sub finish( $self, $output=undef ) {
    return $self->SUPER::finish if !defined $output; # XXX: Minion calls this again after we do inside the task?
    my $run_job = $self->zapp_task;
    my ( $run_id, $task_id ) = $run_job->@{qw( run_id task_id )};

    # Save assignments to child contexts
    # XXX: Make zapp_run_tasks a copy of zapp_plan_tasks
    ; $self->app->log->debug( 'Output: ' . $self->app->dumper( $output ) );
    my $task = $self->app->yancy->get( zapp_run_tasks => $task_id );
    my $output_saves = decode_json( $task->{output} // '[]' );
    my $context = decode_json( $self->zapp_task->{context} );
    for my $save ( @$output_saves ) {
        ; $self->app->log->debug( "Saving: " . $self->app->dumper( $save ) );
        my $schema = get_path_from_schema( $save->{expr}, $self->schema->{output} );
        my $type_name = $save->{type} || $schema->{type};
        my $type = $self->app->zapp->types->{ $type_name }
            or die "Could not find type name $type_name";
        my $value = get_path_from_data( $save->{expr}, $output );
        ; $self->app->log->debug(
            "Building context value: " . $self->app->dumper( {
                name => $save->{name},
                value => $value,
                type => $type_name,
                config => $context->{config},
            } )
        );

        $context->{ $save->{name} } = {
            value => $type->task_output( $context->{config}, $value ),
            type => $type_name,
            # XXX: Task output does not have configuration, but do we
            # want to allow it? It's _complicated_.
            config => $context->{config},
        };
        ; $self->app->log->debug( "Saved context: " . $self->app->dumper( $context->{ $save->{name} } ) );
    }

    if ( my @job_ids = @{ $self->info->{children} } ) {
        $self->app->log->debug( "Saving context to children: " . $self->app->dumper( $context ) );
        for my $job_id ( @{ $self->info->{children} } ) {
            # XXX: Allow alternate unique keys to be used to `get` Yancy items
            my ( $task ) = $self->app->yancy->list( zapp_run_tasks => { job_id => $job_id } );
            $self->app->yancy->backend->set(
                zapp_run_tasks => $task->{task_id} => {
                    context => encode_json( $context ),
                },
            );
        }
    }
    else {
        $self->app->log->debug( 'Saving run output' );
        $self->app->yancy->backend->set(
            zapp_runs => $run_id => {
                output => encode_json( $context ),
            },
        );
    }

    my $ok = $self->SUPER::finish( $output );
    # Set state after so run `finished` timestamp can be set
    $self->set( state => 'finished' );
    return $ok;
}

sub fail( $self, @args ) {
    $self->set( state => 'failed' );
    return $self->SUPER::fail( @args );
}

sub schema( $class ) {
    return {
        input => {
            type => 'array',
        },
        output => {
            type => 'string',
        },
    };
}

1;
