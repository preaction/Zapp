package Zapp::Type;

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Type Value

The type value is returned from the input methods and should contain all
the information needed to use the value in a task. This does not need to
be the actual content that tasks will use, but can be an identifier to
look up that content.

For example, the L<Zapp::Type::File> type stores a path relative to the
application's home directory. When saving plans or starting runs, the
file gets uploaded, saved to the home directory, and the path saved to
the database. When a task needs the file, it gets the full path as
a string.

Another example could be a map of user passwords in a config file. The
type value could be the username, which would be stored in the database
for the plan/run. Then when a task needed the password, it could be
looked up using the username.

XXX: Types are in a hierarchy:

String <-> Boolean
String <-> Integer
String <-> Number <-> Integer
String <-> File
String <-> Enum[String]

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

=head2 plan_input

Process the form value when saving a plan. Return the type value to be
stored in the database.

=cut

sub plan_input( $self, $c, $form_value ) {
    ...;
}

=head2 run_input

Process the form value when saving a run. Return the type value to be
stored in the database.

=cut

sub run_input( $self, $c, $form_value ) {
    ...;
}

=head2 task_input

Convert the type value stored in the database to the value used by the
task.

=cut

sub task_input( $self, $type_value ) {
    ...;
}

=head2 task_output

Convert a value from a task's output into a type value to be stored in
the database.

=cut

sub task_output( $self, $task_value ) {
    ...;
}

=head2 input_field

Get the form field to input this value. Reads the C<@@ input.html.ep> file
from the C<__DATA__> section of the type class.

=cut

sub input_field( $self, $c, $type_value=undef ) {
    my $class = blessed $self;
    my $tmpl = data_section( $class, 'input.html.ep' );
    # XXX: Use Mojo::Template directly to get better names than 'inline
    # template XXXXXXXXXXXX'?
    return $c->render_to_string(
        inline => $tmpl,
        self => $self,
        value => $type_value,
    );
}

1;
