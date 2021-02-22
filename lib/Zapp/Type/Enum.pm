package Zapp::Type::Enum;
use Mojo::Base 'Zapp::Type', -signatures;
use List::Util qw( any first );
use Mojo::Loader qw( data_section );

# XXX: This cannot be used as task output without default options!
# Should we have a way to configure options in task output, or should we
# have a way to disable types for output?

has default_options => sub { undef };

sub new( $class, @args ) {
    my $self = $class->SUPER::new;
    if ( @args ) {
        my @default_options;
        if ( @args == 1 ) {
            @default_options = $args[0]->@*;
        }
        else {
            @default_options = @args;
        }
        $self->default_options([
            map {
                ref $_ eq 'ARRAY'
                ? { label => $_->[0], value => $_->[1] }
                : { label => $_, value => $_ }
            } @default_options
        ]);
    }
    return $self;
}

sub _value_label( $self, $config, $value ) {
    my ( $label ) = first { $_->{value} eq $value } $config->{options}->@*;
    return $label // $value;
}

sub _field_values( $self, $config, $selected_value ) {
    $selected_value //= $config->{options}[ $config->{selected_index} ]{value};
    return [
        map {
            [
                $_->{label}, $_->{value},
                ( selected => 'selected' )x!!( $_->{value} eq $selected_value ),
            ]
        } @{ $config->{options} }
    ];
}

sub _check_value( $self, $options, $value ) {
    $options //= $self->default_options;
    die "Invalid value for enum: $value"
        unless any { $_->{value} eq $value } @{$options};
}

# Form value -> Type value
sub process_config( $self, $c, $form_value ) {
    return $form_value;
}

sub process_input( $self, $c, $config_value, $form_value ) {
    $self->_check_value( $config_value->{options}, $form_value );
    return $form_value;
}

# Type value -> Task value
sub task_input( $self, $config_value, $input_value ) {
    $self->_check_value( $config_value->{options}, $input_value );
    return $input_value;
}

# Task value -> Type value
sub task_output( $self, $config_value, $task_value ) {
    $self->_check_value( $config_value->{options}, $task_value );
    return $task_value;
}

1;
__DATA__
@@ config.html.ep
<%
    my @options = @{
        $config->{options} // $self->default_options // [ {} ]
    };
    $c->log->debug( 'Rendering options: ' . $c->dumper( \@options ) );
    my $selected_index = $config->{selected_index} // 0;
%>
% my $enum_tmpl = begin
    % my ( $i, $opt ) = @_;
    %= text_field "config.options[$i].label", $opt->{label} // '', class => 'form-control'
    %= text_field "config.options[$i].value", $opt->{value} // '', class => 'form-control'
    %= radio_button 'config.selected_index', $i, ( checked => 'checked' )x!!( $i eq $selected_index ), class => 'form-control'
% end
<template id="enum-tmpl"><%= $enum_tmpl->( '#', {} ) %></template>
<div data-zapp-array>
    % for my $i ( 0 .. $#options ) {
        <div data-zapp-array-row class="d-flex">
            %= $enum_tmpl->( $i, $options[$i] )
            <button type="button" data-zapp-array-remove>-</button>
        </div>
    % }
    <button type="button" data-zapp-array-add="#enum-tmpl">+</button>
</div>

@@ input.html.ep
%= select_field 'value', $self->_field_values( $config, $value ), class => 'form-control'

@@ output.html.ep
%= $self->_value_label( $config, $value )

