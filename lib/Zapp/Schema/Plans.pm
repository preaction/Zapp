package Zapp::Schema::Plans;
use Mojo::Base 'Yancy::Model::Schema', -signatures;
use Mojo::JSON qw( encode_json decode_json );

sub name { 'zapp_plans' }
has tasks_schema  => 'plan_tasks';
has inputs_schema => 'plan_inputs';

sub create( $self, $plan ) {
    my @inputs = @{ delete $plan->{inputs} // [] };
    my @tasks = @{ delete $plan->{tasks} // [] };
    my $plan_id = $self->SUPER::create( $plan );

    for my $i ( 0..$#inputs ) {
        $inputs[$i]{plan_id} = $plan_id;
        my $input = { %{ $inputs[$i] }, rank => $i };
        $self->model->schema( $self->inputs_schema )->create( $input );
    }

    my $prev_task_id;
    for my $task ( @tasks ) {
        $task->{plan_id} = $plan_id;
        $task->{parents} = [ $prev_task_id ] if $prev_task_id;
        my $task_id = $self->model->schema( $self->tasks_schema )->create( $task );
        $prev_task_id = $task_id;
    }

    return $plan_id;
}

sub get( $self, $id, %opt ) {
    # Fetch tasks and inputs automatically
    my $plan = $self->SUPER::get( $id );

    my $inputs_schema = $self->model->schema( $self->inputs_schema );
    $plan->{inputs} = $inputs_schema->list({ plan_id => $id }, { order_by => 'rank' })->{items};

    my $tasks_schema = $self->model->schema( $self->tasks_schema );
    $plan->{tasks} = $tasks_schema->list({ plan_id => $id }, { order_by => 'task_id' })->{items};

    return $plan;
}

1;
