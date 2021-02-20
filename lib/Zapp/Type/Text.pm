package Zapp::Type::Text;
use Mojo::Base 'Zapp::Type', -signatures;
use Mojo::Loader qw( data_section );

# XXX: Array type to hold another type
# XXX: Enum type to choose from values of any type
# XXX: EnumArray type to choose one or more values of any type
# XXX: File type to upload files and pass file paths to tasks
# XXX: KeyValue type?

# "die" for validation errors

# Form value -> Type value
sub plan_input( $self, $c, $form_value ) {
    return $form_value;
}
sub run_input( $self, $c, $form_value ) {
    return $form_value;
}

# Type value -> Task value
sub task_input( $self, $type_value ) {
    return $type_value;
}

# Task value -> Type value
sub task_output( $self, $task_value ) {
    return $task_value;
}

1;
__DATA__
@@ input.html.ep
%= text_field 'value', value => $value, class => 'form-control'

@@ output.html.ep
%= $value

