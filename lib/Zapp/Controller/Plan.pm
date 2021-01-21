package Zapp::Controller::Plan;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use List::Util qw( first uniqstr );
use Time::Piece;
use Zapp::Util qw( fill_input get_path_from_data );

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
            $input->{default_value} = decode_json( $input->{default_value} );
        }
    }
    return $plan;
}

sub _get_run( $self, $run_id ) {
    my $run = $self->yancy->get( zapp_runs => $run_id ) || {};
    if ( my $run_id = $run->{run_id } ) {
        $run->{input_values} = decode_json( $run->{input_values} );

        my $plan = $run->{plan} = $self->_get_plan( $run->{plan_id} );
        for my $task ( @{ $plan->{tasks} } ) {
            my $task_id = $task->{task_id};
            my ( $job ) = $self->yancy->list( zapp_run_jobs => { run_id => $run_id, task_id => $task_id } );
            my $minion_job = $self->minion->job( $job->{minion_job_id} );

            my $plan_task = $self->yancy->get( zapp_plan_tasks => $task_id );
            $plan_task->{input} = decode_json( $plan_task->{input} );
            if ( $plan_task->{output} ) {
                $plan_task->{output} = decode_json( $plan_task->{output} );
            }

            # The task run information should be all the Zapp task
            # information and all the Minion job information except for
            # args and result (renamed input and output respectively)
            my $run_task = {
                %$plan_task,
                $minion_job->info->%*,
                %$job,
                tests => [
                    $self->app->yancy->list( zapp_run_tests =>
                        {
                            run_id => $run_id,
                            task_id => $task_id,
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
                $run_task->{input} = fill_input( $run_task->{context}, $run_task->{input} );
            }

            $run_task->{output} = delete $run_task->{result};

            push $run->{tasks}->@*, $run_task;
        }

        my $inputs = $plan->{inputs} = [
            $self->yancy->list( zapp_plan_inputs => { plan_id => $run->{plan_id} }, { order_by => 'name' } ),
        ];
        for my $input ( @$inputs ) {
            $input->{default_value} = decode_json( $input->{default_value} );
            $input->{value} = $run->{input_values}{ $input->{name} };
        }
    }

    $run->{started} = $run->{tasks}[0]{started};
    $run->{finished} = $run->{tasks}[-1]{finished};
    $run->{state} = ( first { $_ ne 'finished' } map { $_->{state} } @{ $run->{tasks} } ) // 'finished';

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
    # XXX: Move to Yancy (Util? Controller?)
    my @params = grep /^$prefix(?:\[\d+\]|\.\w+)/, $self->req->body_params->names->@*;
    my $data;
    for my $param ( @params ) {
        my $value = $self->param( $param );
        my $path = $param =~ s/^$prefix//r;
        my $slot = \( $data ||= '' );
        for my $part ( $path =~ m{((?:\w+|\[\d+\]))(?=\.|\[|$)}g ) {
            if ( $part =~ /^\[(\d+)\]$/ ) {
                my $part_i = $1;
                if ( !ref $$slot ) {
                    $$slot = [];
                }
                $slot = \( $$slot->[ $part_i ] );
                next;
            }
            else {
                if ( !ref $$slot ) {
                    $$slot = {};
                }
                $slot = \( $$slot->{ $part } );
            }
        }
        $$slot = $value;
    }
    return $data;
}

sub save_plan( $self ) {

    my $plan_id = $self->stash( 'plan_id' );
    my $plan = {
        map { $_ => $self->param( $_ ) }
        qw( name description ),
    };
    my $tasks = $self->build_data_from_params( 'task' );
    my $form_inputs = $self->build_data_from_params( 'input' );

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
    }
    if ( @errors ) {
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

    # XXX: Create transaction routine for Yancy::Backend
    # XXX: Create sync routine for Yancy::Backend that takes a set of
    # items and updates the schema to look exactly like that (deleting,
    # updating, inserting as needed)
    if ( $plan_id ) {
        $self->yancy->backend->set( zapp_plans => $plan_id, $plan );
    }
    else {
        $plan_id = $self->yancy->backend->create( zapp_plans => $plan );
    }

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
            my ( @existing_parents ) = $self->yancy->list( zapp_task_parents => { task_id => $task_id } );
            for my $parent ( @existing_parents ) {
                # We're supposed to have this row, so ignore it
                next if grep { $parent->{parent_task_id} eq $_ } ( $parent_task_id );
                # We're not supposed to have this row, so delete it
                $self->yancy->backend->delete( zapp_task_parents => [ $parent->@{qw( task_id parent_task_id )} ] );
            }
            for my $new_parent ( $parent_task_id ) {
                # We already have this row, so ignore it
                next if grep { $new_parent eq $_->{parent_task_id} } @existing_parents;
                # We don't have this row, so create it
                $self->yancy->backend->create( zapp_task_parents => {
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
        my ( @existing_parents ) = $self->yancy->list( zapp_task_parents => { task_id => $task_id } );
        for my $parent ( @existing_parents ) {
            $self->yancy->backend->delete( zapp_task_parents => [ $parent->@{qw( task_id parent_task_id )} ] );
        }
    }

    my %input_to_delete = map { $_->{name} => $_ } $self->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } );
    for my $form_input ( @$form_inputs ) {
        # XXX: Auto-encode/-decode JSON fields in Yancy schema
        for my $json_field ( qw( default_value ) ) {
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
    $self->render( 'zapp/plan/list', plans => \@plans );
}

sub edit_run( $self ) {
    my $plan = $self->_get_plan( $self->stash( 'plan_id' ) );
    $self->render( 'zapp/run/edit', plan => $plan );
}

sub save_run( $self ) {
    my $plan_id = $self->stash( 'plan_id' );
    my $plan = $self->_get_plan( $plan_id );

    my $input = $self->build_data_from_params( 'input' );
    my $run_id = $self->stash( 'run_id' );
    if ( !$run_id ) {
        my $run = $self->app->enqueue( $plan_id, $input );
        $run_id = $run->{run_id};
    }
    else {
        my $run = {
            plan_id => $plan_id,
            # XXX: Auto-encode/-decode JSON fields in Yancy schema
            input_values => encode_json( $input ),
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


1;
