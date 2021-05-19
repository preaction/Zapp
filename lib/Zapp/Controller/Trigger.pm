package Zapp::Controller::Trigger;
# ABSTRACT: Web handlers for trigger management

use Mojo::Base 'Mojolicious::Controller', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Util qw( build_data_from_params );

=method edit

Create or edit a trigger. A C<GET> request shows the form. A C<POST>
request saves the form and returns the user to the plan view.

When creating a new trigger, the C<plan_id> and C<class> params must be
defined. When editing a trigger, the C<trigger_id> param must be
defined.

=cut

sub edit( $self ) {
    if ( $self->req->method eq 'GET' ) {
        my $trigger;
        if ( my $trigger_id = $self->param( 'trigger_id' ) ) {
            $trigger = $self->app->yancy->get( zapp_triggers => $trigger_id );
        }
        else {
            $trigger = {
                type => $self->param( 'type' ),
                plan_id => $self->param( 'plan_id' ),
            };
        }

        # XXX: Auto-decode JSON in Yancy
        $trigger->{config} &&= decode_json( $trigger->{config} );
        my $plan = $self->app->get_plan( $trigger->{plan_id} );

        return $self->render(
            'zapp/trigger/edit',
            trigger => $trigger,
            inputs => $plan->{inputs},
        );
    }

    my $trigger = build_data_from_params( $self );
    $trigger->{$_} &&= encode_json( $trigger->{$_} ) for qw( config input );
    my $trigger_id = $self->param( 'trigger_id' );
    # XXX: Make Yancy set forward to create() when the ID is undef
    if ( $trigger_id ) {
        $self->yancy->set( zapp_triggers => $trigger_id, $trigger );
    }
    else {
        $trigger_id = $self->yancy->create( zapp_triggers => $trigger );
    }

    return $self->redirect_to( 'zapp.list_plans' );
}

1;
