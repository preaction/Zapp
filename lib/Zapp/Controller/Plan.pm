package Zapp::Controller::Plan;
use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw( decode_json encode_json );

# Zapp: Now, like all great plans, my strategy is so simple an idiot
# could have devised it.

sub edit_plan( $self ) {

    #***********************************************
    use Zapp::Task::Request;
    use Zapp::Task::Assert;
    use Zapp::Task::Script;

    #***********************************************

    my $plan = $self->yancy->get( zapp_plans => $self->stash( 'plan_id' ) ) || {};
    if ( my $plan_id = $plan->{plan_id} ) {
        my $tasks = $plan->{tasks} = [
            $self->yancy->list( zapp_tasks => { plan_id => $plan_id }, { order_by => 'task_id' } ),
        ];
        for my $task ( @$tasks ) {
            $task->{args} = decode_json( $task->{args} );
        }

        my $inputs = $plan->{inputs} = [
            $self->yancy->list( zapp_plan_inputs => { plan_id => $plan_id }, { order_by => 'name' } ),
        ];
        for my $input ( @$inputs ) {
            ; $self->log->debug( 'Input default value: ' . $input->{default_value} . ' Decoded: ' . decode_json( $input->{default_value} ) );
            $input->{default_value} = decode_json( $input->{default_value} );
        }
    }

    return $self->render(
        'zapp/plan/edit',
        plan => $plan,
        tasks => [
            qw( Zapp::Task::Assert ),
            qw( Zapp::Task::Request ),
            qw( Zapp::Task::Script ),
        ],
    );
}

sub build_array_from_params( $self, $prefix ) {
    # XXX: Move to Yancy (Util? Controller?)
    # XXX: Break into array/hash routines
    my @params = grep /^$prefix\[\d+\]/, $self->req->body_params->names->@*;
    my @items;
    for my $param ( @params ) {
        my $value = $self->param( $param );
        my ( $i, $path ) = $param =~ m{^$prefix\[(\d+)\]\.(.+)$};
        my $slot = \( $items[ $i ] ||= '' );
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
    return @items;
}

sub save_plan( $self ) {

    my $plan_id = $self->stash( 'plan_id' );
    my $plan = {
        map { $_ => $self->param( $_ ) }
        qw( name description ),
    };

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

    my @tasks = $self->build_array_from_params( 'task' );
    my %tasks_to_delete
        = map { $_->{task_id} => 1 }
        $self->yancy->list( zapp_tasks => { plan_id => $plan_id } );
    my $parent_task_id;
    for my $task ( @tasks ) {
        my $task_id = $task->{task_id};
        # XXX: Auto-encode/-decode JSON fields in Yancy schema
        for my $json_field ( qw( args ) ) {
            $task->{ $json_field } = encode_json( $task->{ $json_field } );
        }

        if ( $task_id ) {
            delete $tasks_to_delete{ $task_id };
            $self->yancy->backend->set( zapp_tasks => $task_id, $task );
        }
        else {
            delete $task->{task_id};
            $task_id = $task->{task_id} = $self->yancy->backend->create( zapp_tasks => {
                %$task, plan_id => $plan_id,
            } );
        }

        if ( $parent_task_id ) {
            my ( @existing_parents ) = $self->yancy->list( zapp_task_parents => { task_id => $task_id } );
            for my $parent ( @existing_parents ) {
                $self->yancy->backend->delete( zapp_task_parents => [ $parent->@{qw( task_id parent_id )} ] );
            }
            $self->yancy->backend->create( zapp_task_parents => {
                task_id => $task_id,
                parent_id => $parent_task_id,
            });
        }
        $parent_task_id = $task_id;
    }

    for my $task_id ( keys %tasks_to_delete ) {
        $self->yancy->delete( zapp_tasks => $task_id );
        my ( @existing_parents ) = $self->yancy->list( zapp_task_parents => { task_id => $task_id } );
        for my $parent ( @existing_parents ) {
            $self->yancy->backend->delete( zapp_task_parents => [ $parent->@{qw( task_id parent_id )} ] );
        }
    }

    my %input_to_delete = map { $_->{name} => $_ } $self->yancy->list( zapp_plan_inputs => { plan_id => $plan_id } );
    my @form_inputs = $self->build_array_from_params( 'input' );
    for my $form_input ( @form_inputs ) {
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

sub list_plans( $self ) {
    my @plans = $self->yancy->list( zapp_plans => {}, {} );
    $self->render( 'zapp/plan/list', plans => \@plans );
}

1;
