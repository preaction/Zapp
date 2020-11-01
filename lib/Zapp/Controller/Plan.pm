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

sub save_plan( $self ) {

    my $plan_id = $self->stash( 'plan_id' );
    my $plan = {
        map { $_ => $self->param( $_ ) }
        qw( name description ),
    };

    # XXX: Allow deep data structures to be created in Yancy
    my @task_params = grep /^task\[\d+\]/, $self->req->body_params->names->@*;
    my @tasks;
    for my $param ( @task_params ) {
        my $value = $self->param( $param );
        my ( $task_num, $path ) = $param =~ m{^task\[(\d+)\]\.(.+)$};
        my $slot = \( $tasks[ $task_num ] ||= '' );
        for my $part ( $path =~ m{((?:\w+|\[\d+\]))(?=\.|\[|$)}g ) {
            if ( $part =~ /^\[(\d+)\]$/ ) {
                my $idx = $1;
                if ( !ref $$slot ) {
                    $$slot = [];
                }
                $slot = \( $$slot->[ $idx ] );
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

    # XXX: Create transaction routine for Yancy::Backend
    if ( $plan_id ) {
        $self->yancy->backend->set( zapp_plans => $plan_id, $plan );
    }
    else {
        $plan_id = $self->yancy->backend->create( zapp_plans => $plan );
    }

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

    $self->redirect_to( 'zapp.edit_plan' => { plan_id => $plan_id } );
}

1;
