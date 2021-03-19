package Zapp::Task::Action::Confirm;

=head1 DESCRIPTION

The Confirm action prompts a user to click a button to proceed with the run.

=head1 SEE ALSO

L<Zapp::Task::Action>

=cut

use Mojo::Base 'Zapp::Task::Action', -signatures;

sub run( $self, $task_input ) {
    my $form_input = $self->info->{notes}{input};
    # Clicking a button adds the name to the form input
    if ( exists $form_input->{confirm} ) {
        ; $self->app->log->debug( 'Confirmed!' );
        return $self->finish( { is_success => 1 } );
    }
    ; $self->app->log->debug( 'Cancelled!' );
    return $self->fail( { is_success => 0 } );
}

1;
__DATA__
@@ input.html.ep
<%
    my $input = stash( 'input' ) // { prompt => 'Are you sure you want to continue?' };
%>
<div class="form-row">
    <div class="col-auto">
        <label for="prompt">Prompt</label>
        %= text_field 'prompt', value => $input->{prompt}, class => 'form-control'
    </div>
</div>

@@ action.html.ep
<h3>Confirm</h3>
<p><%= $input->{prompt} %></p>
<button name="confirm" class="btn btn-success">Confirm</button>
<button name="cancel" class="btn btn-danger">Cancel</button>

