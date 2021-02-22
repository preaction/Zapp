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
sub process_config( $self, $c, $form_value ) {
    return $form_value;
}

sub process_input( $self, $c, $config_value, $form_value ) {
    return $form_value // $config_value;
}

# Type value -> Task value
sub task_input( $self, $config_value, $input_value ) {
    return $input_value;
}

# Task value -> Type value
sub task_output( $self, $config_value, $task_value ) {
    return $task_value;
}

1;
__DATA__
@@ input.html.ep
%= text_field 'value', value => $value // $config, class => 'form-control'

@@ config.html.ep
<label for="config">Value</label>
%= text_field 'config', value => $config, class => 'form-control'

@@ output.html.ep
%= $value

