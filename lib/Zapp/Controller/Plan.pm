package Zapp::Controller::Plan;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use List::Util qw( first uniqstr );
use Mojo::Loader qw( data_section );
use Time::Piece;
use Zapp::Util qw( get_slot_from_data fill_input get_path_from_data );

# Zapp: Now, like all great plans, my strategy is so simple an idiot
# could have devised it.

sub _get_plan( $self, $plan_id ) {
    my $plan = $self->yancy->get( zapp_plans => $plan_id ) || {};
    if ( my $plan_id = $plan->{plan_id} ) {
        my $tasks = $plan->{tasks} = [
            $self->yancy->list( zapp_plan_tasks => { plan_id => $plan_id }, { order_by => 'task_id' } ),
        ];
        for my $task ( @$tasks ) {
            $task->{input} = decode_json( $task->{input} );
            $task->{output} = decode_json( $task->{output} // '[]' );
            $task->{tests} = [
                $self->yancy->list(
                    zapp_plan_tests =>
                    {
                        task_id => $task->{task_id},
                    },
                    {
                        order_by => 'test_id',
                    },
                )
            ];
        }

        my $inputs = $plan->{inputs} = [
            $self->yancy->list( zapp_plan_inputs => { plan_id => $plan_id }, { order_by => 'name' } ),
        ];
        for my $input ( @$inputs ) {
            $input->{value} = decode_json( $input->{value} );
        }
    }
    return $plan;
}

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
                $values{ $name } = $type->task_input( { run_id => $run_id }, { task_id => $task->{task_id} }, $input->{value} );
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
        $run->{input_values} = decode_json( $run->{input_values} );

        $run->{tasks} = $self->_get_run_tasks( $run_id );

        my $inputs = [
            $self->yancy->list( zapp_run_inputs => { run_id => $run_id }, { order_by => 'name' } ),
        ];
        for my $input ( @$inputs ) {
            $input->{value} = decode_json( $input->{value} );
            $input->{value} = $run->{input_values}{ $input->{name} };
        }
    }

    return $run;
}

sub edit_plan( $self ) {
    my @tasks =
        sort grep { !ref $_ && eval { $_->isa('Zapp::Task') } }
        values $self->minion->tasks->%*;
    my $plan = $self->stash( 'plan' ) || $self->_get_plan( $self->stash( 'plan_id' ) );
    return $self->render(
        'zapp/plan/edit',
        plan => $plan,
        tasks => \@tasks,
    );
}

sub build_data_from_params( $self, $prefix ) {
    my $data = '';
    # XXX: Move to Yancy (Util? Controller?)
    my @params = grep /^$prefix(?:\[\d+\]|\.\w+)/, $self->req->params->names->@*;
    for my $param ( @params ) {
        ; $self->log->debug( "Param: $param" );
        my $value = $self->param( $param );
        my $path = $param =~ s/^$prefix//r;
        my $slot = get_slot_from_data( $path, \$data );
        $$slot = $value;
    }
    my @uploads = grep $_->name =~ /^$prefix(?:\[\d+\]|\.\w+)/, $self->req->uploads->@*;
    for my $upload ( @uploads ) {
        ; $self->log->debug( "Upload: " . $upload->name );
        my $path = $upload->name =~ s/^$prefix//r;
        my $slot = get_slot_from_data( $path, \$data );
        $$slot = $upload;
    }
    ; $self->log->debug( "Build data: " . $self->dumper( $data ) );
    return $data ne '' ? $data : undef;
}

sub save_plan( $self ) {

    my $plan_id = $self->stash( 'plan_id' );
    my $plan = {
        map { $_ => $self->param( $_ ) }
        qw( name description ),
    };
    my $tasks = $self->build_data_from_params( 'task' );
    my $form_inputs = $self->build_data_from_params( 'input' );

    # XXX: Create transaction routine for Yancy::Backend
    if ( $plan_id ) {
        $self->yancy->backend->set( zapp_plans => $plan_id, $plan );
    }
    else {
        $plan_id = $self->yancy->backend->create( zapp_plans => $plan );
    }
    $plan->{plan_id} = $plan_id;

    # Validate all incoming data.
    my @errors;
    for my $i ( 0..$#$form_inputs ) {
        my $input = $form_inputs->[ $i ];
        if ( $input->{name} =~ /\P{Word}/ ) {
            my @chars = uniqstr sort $input->{name} =~ /\P{Word}/g;
            push @errors, {
                name => "input[$i].name",
                error => qq{Input name "$input->{name}" has invalid characters: }
                    . join( '', map { "<kbd>$_</kbd>" } @chars ),
            };
        }
        my $type = $self->app->zapp->types->{ $input->{type} }
            or die qq{Could not find type "$input->{type}"};
        eval {
            $input->{value} = $type->plan_input( $self, $plan, $input->{value} );
        };
        if ( $@ ) {
            push @errors, {
                name => "input[$i].name",
                error => qq{Error validating input "$input->{name}" type "$input->{type}" value "$input->{value}": $@},
            };
        }
    }
    if ( @errors ) {
        $self->log->error( "Error saving plan: " . $self->dumper( \@errors ) );
        $self->stash(
            status => 400,
            plan => {
                %$plan,
                tasks => $tasks,
                inputs => $form_inputs,
            },
            errors => \@errors,
        );
        return $self->edit_plan;
    }

    # XXX: Create sync routine for Yancy::Backend that takes a set of
    # items and updates the schema to look exactly like that (deleting,
    # updating, inserting as needed)
    my %tasks_to_delete
        = map { $_->{task_id} => 1 }
        $self->yancy->list( zapp_plan_tasks => { plan_id => $plan_id } );
    my $parent_task_id;
    for my $task ( @$tasks ) {
        my $task_id = $task->{task_id};
        my $tests = $task->{tests} ? delete $task->{tests} : [];

        $task->{output} //= [];
        # XXX: Auto-encode/-decode JSON fields in Yancy schema
        for my $json_field ( qw( input output ) ) {
            $task->{ $json_field } = encode_json( $task->{ $json_field } );
        }

        if ( $task_id ) {
            delete $tasks_to_delete{ $task_id };
            $self->yancy->backend->set( zapp_plan_tasks => $task_id, $task );
        }
        else {
            delete $task->{task_id};
            $task_id = $task->{task_id} = $self->yancy->backend->create( zapp_plan_tasks => {
                %$task, plan_id => $plan_id,
            } );
        }

        if ( $parent_task_id ) {
            my ( @existing_parents ) = $self->yancy->list( zapp_plan_task_parents => { task_id => $task_id } );
            for my $parent ( @existing_parents ) {
                # We're supposed to have this row, so ignore it
                next if grep { $parent->{parent_task_id} eq $_ } ( $parent_task_id );
                # We're not supposed to have this row, so delete it
                $self->yancy->backend->delete( zapp_plan_task_parents => [ $parent->@{qw( task_id parent_task_id )} ] );
            }
            for my $new_parent ( $parent_task_id ) {
                # We already have this row, so ignore it
                next if grep { $new_parent eq $_->{parent_task_id} } @existing_parents;
                # We don't have this row, so create it
                $self->yancy->backend->create( zapp_plan_task_parents => {
                    task_id => $task_id,
                    parent_task_id => $parent_task_id,
                });
            }
        }
        $parent_task_id = $task_id;

        if ( @$tests ) {
            my %tests_to_delete
                = map { $_->{test_id} => 1 }
                $self->yancy->list( zapp_plan_tests => { plan_id => $plan_id, task_id => $task_id } );

            for my $test ( @$tests ) {
                my $test_id = $test->{test_id};
                if ( $test_id ) {
                    delete $tests_to_delete{ $test_id };
                    $self->yancy->backend->set( zapp_plan_tests => $test_id, $test );
                }
                else {
                    delete $test->{test_id};
                    $test_id = $test->{test_id} = $self->yancy->backend->create( zapp_plan_tests => {
                        %$test, plan_id => $plan_id, task_id => $task_id,
                    } );
                }
            }

            for my $test_id ( keys %tests_to_delete ) {
                $self->yancy->delete( zapp_plan_tests => $test_id );
            }

        }
    }

    for my $task_id ( keys %tasks_to_delete ) {
        $self->yancy->delete( zapp_plan_tasks => $task_id );
        my ( @existing_parents ) = $self->yancy->list( zapp_plan_task_parents => { task_id => $task_id } );
        for my $parent ( @existing_parents ) {
            $self->yancy->backend->delete( zapp_plan_task_parents => [ $parent->@{qw( task_id parent_task_id )} ] );
        }
    }

    my %input_to_delete = map { $_->{name} => $_ } $self->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } );
    for my $form_input ( @$form_inputs ) {
        ; $self->log->debug( "Input: " . $self->dumper( $form_input ) );
        # XXX: Auto-encode/-decode JSON fields in Yancy schema
        for my $json_field ( qw( value ) ) {
            $form_input->{ $json_field } = encode_json( $form_input->{ $json_field } );
        }

        my $name = $form_input->{name};
        if ( $input_to_delete{ $name } ) {
            delete $input_to_delete{ $name };
            $self->yancy->backend->set(
                zapp_plan_inputs => { plan_id => $plan_id, $form_input->%{'name'} }, $form_input,
            );
        }
        else {
            $self->yancy->backend->create(
                zapp_plan_inputs => { %$form_input, plan_id => $plan_id },
            );
        }
    }
    for my $name ( keys %input_to_delete ) {
        # XXX: Fix yancy backend composite keys to allow arrayref of
        # ordered columns
        $self->yancy->backend->delete( zapp_plan_inputs => { plan_id => $plan_id, name => $name } );
    }

    $self->redirect_to( 'zapp.edit_plan' => { plan_id => $plan_id } );
}

sub delete_plan( $self ) {
    my $plan_id = $self->stash( 'plan_id' );
    my $plan = $self->yancy->get( zapp_plans => $plan_id );
    if ( $self->req->method eq 'GET' ) {
        return $self->render(
            'zapp/plan/delete',
            plan => $plan,
        );
    }
    $self->yancy->delete( zapp_plans => $plan_id );
    $self->redirect_to( 'zapp.list_plans' );
}

sub list_plans( $self ) {
    my @plans = $self->yancy->list( zapp_plans => {}, {} );
    for my $plan ( @plans ) {
        my ( $last_run ) = $self->yancy->list(
            zapp_runs => {
                $plan->%{'plan_id'},
            },
            { order_by => { -desc => [qw( created started finished )] } },
        );
        next if !$last_run;

        $plan->{ last_run } = $last_run;
    }
    # XXX: Order should be:
    #   1. Jobs that have no started
    #   2. Jobs that have no finished
    #   3. Jobs by finished datetime
    #   4. Jobs by started datetime
    #   5. Jobs by created datetime
    #   6. Plans by created datetime
    @plans = sort {
        !!( $b->{last_run} // '' ) cmp !!( $a->{last_run} // '' )
        || (
            defined $a->{last_run} && (
                ( $b->{last_run}{state} =~ /(in)?active/n ) cmp ( $a->{last_run}{state} =~ /(in)?active/n )
                || $b->{last_run}{finished} cmp $a->{last_run}{finished}
                || $b->{last_run}{started} cmp $a->{last_run}{started}
            )
        )
        || $b->{created} cmp $a->{created}
    } @plans;
    $self->render( 'zapp/plan/list', plans => \@plans );
}

sub edit_run( $self ) {
    my $plan = $self->_get_plan( $self->stash( 'plan_id' ) );
    $self->render( 'zapp/run/edit', plan => $plan );
}

sub save_run( $self ) {
    my $plan_id = $self->stash( 'plan_id' );
    my $plan = $self->_get_plan( $plan_id );

    my $input_fields = $self->build_data_from_params( 'input' );
    my $input_values = {};
    for my $input ( @$input_fields ) {
        my $type = $self->app->zapp->types->{ $input->{type} }
            or die qq{Could not find type "$input->{type}"};
        $input_values->{ $input->{name} } = {
            type => $input->{type},
            value => $type->run_input( $self, { run_id => time }, $input->{value} ),
        };
    }

    my $run_id = $self->stash( 'run_id' );
    if ( !$run_id ) {
        my $run = $self->app->enqueue( $plan_id, $input_values );
        $run_id = $run->{run_id};
    }
    else {
        my $run = {
            plan_id => $plan_id,
            # XXX: Auto-encode/-decode JSON fields in Yancy schema
            input_values => encode_json( $input_values ),
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
