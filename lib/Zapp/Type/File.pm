package Zapp::Type::File;
use Mojo::Base 'Zapp::Type', -signatures;
use Mojo::File;

has path => sub( $self ) { $self->app->home->child( 'uploads' ) };

# "die" for validation errors

sub _input( $self, $c, $type, $type_id, $upload ) {
    my ( $input_num ) = $upload->name =~ m{^input\[(\d+)\]};
    ; $c->log->debug( "Type: $type, $type_id, $input_num" );
    my $dir = $self->path->child( $type, $type_id, 'input', $input_num );
    $dir->make_path;
    my $file = $dir->child( $upload->filename );
    ; $c->log->debug( "Saving file: $file" );
    $upload->move_to( $file );
    return $file->to_rel( $self->path );
}

# Form value -> Type value
sub plan_input( $self, $c, $plan, $form_value ) {
    return $self->_input( $c, plan => $plan->{plan_id}, $form_value );
}

# Form value -> Type value
sub run_input( $self, $c, $run, $form_value ) {
    return $self->_input( $c, run => $run->{run_id}, $form_value );
}

# For display on run view pages
sub display_value( $self, $c, $type_value ) {
    return $self->app->home->child( $type_value )->basename;
}

# Type value -> Task value
sub task_input( $self, $run, $task, $type_value ) {
    return $self->path->child( $type_value )->to_abs;
}

# Task value -> Type value
sub task_output( $self, $run, $task, $task_value ) {
    # Task gave us a path. Save the path and return the saved path.
    my $output_file = Mojo::File->new( $task_value );
    my $task_dir = $self->path->child( run => $run->{run_id}, task => $task->{task_id} );
    $task_dir->make_path;
    my $task_file = $task_dir->child( $output_file->basename );
    $output_file->copy_to( $task_file );
    return $task_file->to_rel( $self->path );
}

1;
__DATA__
@@ input.html.ep
%= file_field 'value', value => $value, class => 'form-control'

@@ output.html.ep
%# Show a link to download the file
%= link_to $value => $value

