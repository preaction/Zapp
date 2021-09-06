package Zapp::Schema::PlanTasks;
use Mojo::Base 'Yancy::Model::Schema', -signatures;
use Mojo::JSON qw( encode_json decode_json );

sub name { 'zapp_plan_tasks' }

sub create( $self, $task ) {
    my @parents = @{ delete $task->{parents} // [] };
    $task->{input} &&= encode_json( $task->{input} );
    my $task_id = $self->SUPER::create( $task );
    for my $parent_id ( @parents ) {
        $self->model->schema( 'zapp_plan_task_parents' )->create({
            task_id => $task_id,
            parent_task_id => $parent_id,
        });
    }
    return $task_id;
}

sub build_item( $self, $item ) {
    $item->{input} &&= decode_json( $item->{input} );
    return $self->SUPER::build_item( $item );
}

1;
