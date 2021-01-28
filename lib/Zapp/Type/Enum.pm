package Zapp::Type::Enum;
use Mojo::Base 'Zapp::Type', -signatures;
use List::Util qw( any );
use Mojo::Loader qw( data_section );

has values => sub { [] };

sub new( $class, @args ) {
    my $self = $class->SUPER::new;
    if ( @args == 1 ) {
        $self->values( $args[0] );
    }
    else {
        $self->values( \@args );
    }
    return $self;
}

sub _value_label( $self, $value ) {
    for my $opt ( @{ $self->values } ) {
        my ( $opt_label, $opt_value ) = ref $opt eq 'ARRAY' ? @$opt : ( $opt, $opt );
        return $opt_label if $opt_value eq $value;
    }
    return $value;
}

sub _field_values( $self, $selected_value ) {
    $selected_value //= '';
    my @field_values;
    for my $opt ( @{ $self->values } ) {
        my ( $opt_label, $opt_value ) = ref $opt eq 'ARRAY' ? @$opt : ( $opt, $opt );
        push @field_values, [
            $opt_label, $opt_value,
            ( selected => 'selected' )x!!( $opt_value eq $selected_value ),
        ];
    }
    return \@field_values;
}

sub _check_value( $self, $value ) {
    die "Invalid value for enum: $value"
        unless any { ref $_ eq 'ARRAY' ? $_->[1] eq $value : $_ eq $value }
            $self->values->@*;
}

# Form value -> Type value
sub plan_input( $self, $c, $plan, $form_value ) {
    $self->_check_value( $form_value );
    return $form_value;
}

sub run_input( $self, $c, $run, $form_value ) {
    $self->_check_value( $form_value );
    return $form_value;
}

# Type value -> Task value
sub task_input( $self, $run, $task, $type_value ) {
    $self->_check_value( $type_value );
    return $type_value;
}

# Task value -> Type value
sub task_output( $self, $run, $task, $task_value ) {
    $self->_check_value( $task_value );
    return $task_value;
}

1;
__DATA__
@@ input.html.ep
%= select_field 'value', $self->_field_values( $value ), class => 'form-control'

@@ output.html.ep
%= $self->_value_label( $value )

