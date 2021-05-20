package Zapp::Task::Action;

=head1 SYNOPSIS

    package My::Task::Action;
    use Mojo::Base 'Zapp::Task::Action', -signatures;

    sub prepare( $self, $input ) {
        # Notify user of input
        ...;
        # Call superclass to show input form on run page
        $self->SUPER::prepare( $self, $input );
    }

    sub action( $self, $task_input, $c, $form_input ) {
        # Process form input
        return $self->SUPER::action( $task_input, $c, $form_input );
    }

    sub run( $self, $task_input ) {
        my $form_input = $self->info->{notes}{input};
        # Do something with input
        ...;
        # Call superclass to finish
        $self->SUPER::run( $c, $task_input, $form_input );
    }

    1;
    __DATA__
    @@ action.html.ep
    %# Display form for user input

=head1 DESCRIPTION

Actions are L<Task classes|Zapp::Task> that prompt for user input and
then wait. While they are waiting, Action classes may display a button,
an input form, or other content on the run page.

Unlike regular Tasks, custom Actions have three steps:

=over

=item prepare

The L<prepare step|/prepare> is run by a Worker. This can be extended to perform any
necessary notifications or setup. Once the action is prepared, the user may see
the L<action_field|/action_field> on the Run page.

=item action

The L<action step|/action> is run by the web application when a user
interacts with the L<action field|/action_field>. The form input is
stored in the C<input> note (see L<Minion::Job/info>).

=item run

The L<run step|/run> is run by the worker after the user has interacted
with the L<action field|/action_field>. The default behavior is to
simply finish the job successfully with the user's input. Override this
for custom behavior.

=back

=head1 SEE ALSO

L<Zapp::Task::Action::Confirm>, L<Zapp::Task>, L<Zapp>

=cut

use Mojo::Base 'Zapp::Task', -signatures;
use Mojo::Loader qw( data_section );

my $DELAY = 60*60*24*365; # Next year

sub execute( $self ) {
    my $notes = $self->info->{notes};
    return $self->SUPER::execute if $notes->{input};
    if ( $self->zapp_task->{state} ne 'waiting' ) {
        $self->app->log->info( 'Preparing action ' . $self->zapp_task->{task_id} );
        return $self->prepare( @{ $self->args } );
    }
    $self->app->log->info( 'Tried to run waiting action before input' );
    return $self->retry({ delay => $DELAY });
}

sub prepare( $self, $task_input ) {
    # Delay re-running the job for a while
    $self->retry({ delay => $DELAY });
    # Update the Zapp status to display the action form
    $self->set(
        state => 'waiting',
    );
    return;
}

sub action_field( $self, $c, $task_input ) {
    my $class = blessed $self;
    my $tmpl = data_section( $class, 'action.html.ep' );
    return '' if !$tmpl;
    # XXX: Use Mojo::Template directly to get better names than 'inline
    # template XXXXXXXXXXXX'?
    return $c->render_to_string(
        inline => $tmpl,
        self => $self,
        input => $task_input,
    );
}

sub action( $self, $c, $task_input, $form_input ) {
    $self->note( input => $form_input );
    $self->set( state => 'inactive' );
    $self->retry({ delay => -1 });
}

sub run( $self, $task_input ) {
    $self->finish( $self->notes->{input} );
}

1;
__DATA__
