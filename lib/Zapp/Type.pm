package Zapp::Type;
# ABSTRACT: Input/output handling for data types

=head1 SYNOPSIS

    package My::Type;
    use Mojo::Base 'Zapp::Type';
    sub process_config( $self, $c, $form_value ) {
        # Return the $config_value
    }

    sub process_input( $self, $c, $config_value, $form_value ) {
        # Return the $input_value
    }

    sub task_input( $self, $config_value, $input_value ) {
        # Return the $task_value
    }

    sub task_output( $self, $config_value, $task_value ) {
        # Return the $input_value
    }

    __DATA__
    @@ config.html.ep
    %# Form to configure the input

    @@ input.html.ep
    %# Form for the user to fill in

    @@ output.html.ep
    %# Template to display the value

=head1 DESCRIPTION

This is the base class for Zapp types. Types are configured when
building a plan, then filled out by the user when running the plan.
Tasks then get the type's value as input, and can return a value
of the given type.

=head2 Type Value

The type value returned from L</process_input> should contain all the
information needed to use the value in a task. This does not need to be
the actual content that tasks will use, but can be an identifier to look
up that content.

For example, the L<Zapp::Type::File> type stores a path relative to the
application's home directory. When saving plans or starting runs, the
file gets uploaded, saved to the home directory, and the path saved to
the database. When a task needs the file, it gets the full path as
a string.

Another example could be a map of user passwords in a config file. The
type value could be the username, which would be stored in the database
for the plan/run. Then when a task needed the password, it could be
looked up using the username.

=head1 SEE ALSO

=cut

use Mojo::Base -base, -signatures;
use Scalar::Util qw( blessed );
use Mojo::Loader qw( data_section );

=head1 ATTRIBUTES

=head2 app

The application object. A L<Zapp> object.

=cut

has app =>;

=head1 METHODS

=head2 config_field

Get the field for configuration input. Reads the C<@@ config.html.ep>
file from the C<__DATA__> section of the type class.

=cut

sub config_field( $self, $c, $config_value=undef ) {
    my $class = blessed $self;
    my $tmpl = data_section( $class, 'config.html.ep' );
    return '' if !$tmpl;
    # XXX: Use Mojo::Template directly to get better names than 'inline
    # template XXXXXXXXXXXX'?
    return $c->render_to_string(
        inline => $tmpl,
        self => $self,
        config => $config_value,
    );
}

=head2 process_config

Process the form value for configuring this type. Return the type config
to be stored in the database.

=cut

sub process_config( $self, $c, $form_value ) {
    ...;
}

=head2 input_field

Get the field for user input. Reads the C<@@ input.html.ep> file from
the C<__DATA__> section of the type class.

=cut

sub input_field( $self, $c, $config_value, $input_value=undef ) {
    my $class = blessed $self;
    my $tmpl = data_section( $class, 'input.html.ep' );
    # XXX: Use Mojo::Template directly to get better names than 'inline
    # template XXXXXXXXXXXX'?
    return $c->render_to_string(
        inline => $tmpl,
        self => $self,
        config => $config_value,
        value => $input_value,
    );
}

=head2 process_input

Process the form value when saving a run. Return the type value to be
stored in the database.

=cut

sub process_input( $self, $c, $config_value, $form_value ) {
    ...;
}

=head2 task_input

Convert the type value stored in the database to the value used by the
task.

=cut

sub task_input( $self, $config_value, $input_value ) {
    ...;
}

=head2 task_output

Convert a value from a task's output into a type value to be stored in
the database.

=cut

sub task_output( $self, $config_value, $task_value ) {
    ...;
}

=head2 display_value

Show the value on the run page.

=cut

sub display_value( $self, $c, $config_value, $input_value ) {
    my $class = blessed $self;
    my $tmpl = data_section( $class, 'output.html.ep' );
    # XXX: Use Mojo::Template directly to get better names than 'inline
    # template XXXXXXXXXXXX'?
    return $c->render_to_string(
        inline => $tmpl,
        self => $self,
        config => $config_value,
        value => $input_value,
    );
}

1;
