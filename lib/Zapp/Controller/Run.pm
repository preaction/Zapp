package Zapp::Controller::Run;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Mojo::Loader qw( data_section );
use Time::Piece;
use Zapp::Util qw( fill_input build_data_from_params );

sub _get_run_tasks( $self, $run_id ) {
    my @run_tasks;
    for my $task ( $self->yancy->list( zapp_run_tasks => { run_id => $run_id } ) ) {
        my $minion_job = $self->minion->job( $task->{job_id} );

        $task->{input} = decode_json( $task->{input} );
        if ( $task->{output} ) {
            $task->{output} = decode_json( $task->{output} );
        }

        # The task run information should be all the Zapp task
        # information and all the Minion job information except for
        # args and result (renamed input and output respectively)
        my $run_task = {
            ( $minion_job ? $minion_job->info->%* : () ),
            %$task,
            tests => [
                $self->app->yancy->list( zapp_run_tests =>
                    {
                        $task->%{qw( run_id task_id )},
                    },
                    {
                        order_by => 'test_id',
                    },
                ),
            ],
        };

        delete $run_task->{args};
        if ( $run_task->{context} ) {
            $run_task->{context} = decode_json( $run_task->{context} );
            my %values;
            for my $name ( keys %{ $run_task->{context} } ) {
                my $input = $run_task->{context}{ $name };
                my $type = $self->app->zapp->types->{ $input->{type} }
                    or die qq{Could not find type "$input->{type}"};
                $values{ $name } = $type->task_input( $input->{config}, $input->{value} );
            }
            $run_task->{input} = fill_input( \%values, $run_task->{input} );
        }

        $run_task->{output} = delete $run_task->{result};
        push @run_tasks, $run_task;
    }

    return \@run_tasks,
}

sub _get_run( $self, $run_id ) {
    my $run = $self->yancy->get( zapp_runs => $run_id ) || {};
    if ( my $run_id = $run->{run_id} ) {
        # XXX: Run input should be array in rank order
        $run->{input} = decode_json( $run->{input} );
        $run->{output} = decode_json( $run->{output} // '{}' );
        $run->{tasks} = $self->_get_run_tasks( $run_id );
    }
    return $run;
}

sub edit_run( $self ) {
    my $plan = $self->app->get_plan( $self->stash( 'plan_id' ) );
    $self->render( 'zapp/run/edit', plan => $plan );
}

sub save_run( $self ) {
    my $plan_id = $self->stash( 'plan_id' );
    my $plan = $self->app->get_plan( $plan_id );

    my $input_fields = build_data_from_params( $self, 'input' );
    my $run_input = {};
    for my $i ( 0..$#$input_fields ) {
        my $input = $input_fields->[ $i ];
        my $type = $self->app->zapp->types->{ $input->{type} }
            or die qq{Could not find type "$input->{type}"};
        my $config = $input->{config} // $plan->{inputs}[ $i ]{config};
        $run_input->{ $input->{name} } = {
            type => $input->{type},
            config => $config,
            value => $type->process_input( $self, $config, $input->{value} ),
        };
    }
    ; $self->log->debug( 'Run input: ' . $self->dumper( $run_input ) );

    my $run_id = $self->stash( 'run_id' );
    if ( !$run_id ) {
        my $run = $self->app->enqueue( $plan_id, $run_input );
        $run_id = $run->{run_id};
    }
    else {
        my $run = {
            plan_id => $plan_id,
            # XXX: Auto-encode/-decode JSON fields in Yancy schema
            input => encode_json( $run_input ),
        };
        $self->yancy->set( zapp_runs => $run_id, $run );
    }

    $self->redirect_to( 'zapp.get_run' => { run_id => $run_id } );
}

sub get_run( $self ) {
    my $run_id = $self->stash( 'run_id' );
    my $run = $self->_get_run( $run_id );

    if ( $run->{started} ) {
        $run->{started} = Time::Piece->new( $run->{started} )->strftime( '%Y-%m-%d %H:%M:%S' );
    }
    if ( $run->{finished} ) {
        $run->{finished} = Time::Piece->new( $run->{finished} )->strftime( '%Y-%m-%d %H:%M:%S' );
    }

    $self->render( 'zapp/run/view', run => $run );
}

sub stop_run( $self ) {
    my $run_id = $self->stash( 'run_id' );
    my $run = $self->_get_run( $run_id ) || return $self->reply->not_found;

    if ( $self->req->method eq 'GET' ) {
        return $self->render(
            'zapp/run/note',
            heading => 'Stop Run',
            next => 'zapp.stop_run_confirm',
        );
    }

    # Add the note
    $self->yancy->create( zapp_run_notes => {
        $run->%{qw( run_id )},
        event => 'stop',
        note => $self->param( 'note' ),
    } );

    # Stop inactive jobs
    for my $task ( $run->{tasks}->@* ) {
        my $job_id = $task->{job_id};
        my $job = $self->minion->job( $job_id ) || next;
        next if $job->info->{state} ne 'inactive';
        $job->remove;
        $self->yancy->backend->set(
            zapp_run_tasks => $task->{task_id},
            {
                state => 'stopped',
            },
        );
    }

    # Stop run
    $self->yancy->backend->set(
        zapp_runs => $run_id,
        {
            state => 'stopped',
        },
    );

    return $self->redirect_to( 'zapp.get_run' => { run_id => $run_id } );
}

sub start_run( $self ) {
    my $run_id = $self->stash( 'run_id' );
    my $run = $self->_get_run( $run_id ) || return $self->reply->not_found;

    # Requeue all jobs that were stopped
    my %task_jobs;
    for my $task ( $run->{tasks}->@* ) {
        ; $self->log->debug( 'Requeueing task: ' . $self->dumper( $task ) );
        if ( $task->{state} ne 'stopped' ) {
            $task_jobs{ $task->{task_id} } = $task->{job_id};
            next;
        }

        my $old_job_id = $task->{job_id};
        my %job_opts;
        if ( my @parents = $self->yancy->list( zapp_run_task_parents => { $task->%{'task_id'} } ) ) {
            next if grep { !$task_jobs{ $_->{parent_task_id} } } @parents;
            $job_opts{ parents } = [
                map $task_jobs{ $_ }, @parents
            ];
        }

        my $args = $task->{input};
        if ( ref $args ne 'ARRAY' ) {
            $args = [ $args ];
        }

        $self->log->debug( sprintf 'Enqueuing task %s', $task->{class} );
        my $new_job_id = $self->minion->enqueue(
            $task->{class} => $args,
            \%job_opts,
        );
        $task_jobs{ $task->{ task_id } } = $new_job_id;

        $self->yancy->backend->set(
            zapp_run_tasks => $task->{task_id},
            {
                job_id => $new_job_id,
                state => 'inactive',
            },
        );
    }

    $self->yancy->backend->set(
        zapp_runs => $run_id,
        {
            state => 'active',
        },
    );

    return $self->redirect_to( 'zapp.get_run' => { run_id => $run_id } );
}

sub kill_run( $self ) {
    my $run_id = $self->stash( 'run_id' );
    my $run = $self->_get_run( $run_id ) || return $self->reply->not_found;

    if ( $self->req->method eq 'GET' ) {
        return $self->render(
            'zapp/run/note',
            heading => 'Kill Run',
            next => 'zapp.kill_run_confirm',
        );
    }

    # Add the note
    ; $self->log->debug( 'Note: ' . $self->param( 'note' ) );
    $self->yancy->create( zapp_run_notes => {
        $run->%{qw( run_id )},
        event => 'kill',
        note => $self->param( 'note' ),
    } );

    # Kill inactive and active jobs
    for my $task ( $run->{tasks}->@* ) {
        my $job_id = $task->{job_id};
        my $job = $self->minion->job( $job_id ) || next;
        next if $job->info->{state} !~ qr{inactive|active};
        if ( $job->info->{state} eq 'active' ) {
            $self->minion->broadcast( 'kill', [ TERM => $job_id ]);
        }
        else {
            $job->remove;
        }
        $self->yancy->backend->set(
            zapp_run_tasks => $task->{task_id},
            {
                state => 'killed',
            },
        );
    }

    # Kill run
    $self->yancy->backend->set(
        zapp_runs => $run_id,
        {
            state => 'killed',
            finished => Time::Piece->new->datetime,
        },
    );

    return $self->redirect_to( 'zapp.get_run' => { run_id => $run_id } );
}

sub get_run_task( $self ) {
    my $run_id = $self->stash( 'run_id' );
    my $task_id = $self->stash( 'task_id' );
    my ( $run_task ) = grep { $_->{task_id} eq $task_id } $self->_get_run_tasks( $run_id )->@*
        or return $self->reply->not_found;
    my $template = data_section( $run_task->{class}, 'output.html.ep' );
    return $self->render( inline => $template, task => $run_task );
}

1;
