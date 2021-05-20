package Zapp::Trigger;
# ABSTRACT: Trigger a plan from an event

=head1 SYNOPSIS

    package My::Trigger;
    use Mojo::Base 'Zapp::Trigger', -signatures;

    sub install( $self, $app, $config={} ) {
        $self->SUPER::install( $app, $config );
        # Set up trigger to call $self->enqueue when needed
    }

    __DATA__
    @@ config.html.ep
    %# Form to configure trigger

=head1 DESCRIPTION

This is the base class for Zapp triggers. Triggers handle events and run
configured plans. Triggers can accept configuration and plan input.

=head1 SEE ALSO

L<Zapp>

=cut

use Mojo::Base -base, -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Scalar::Util qw( blessed );
use Mojo::Loader qw( data_section );

=attr app

The application object.

=cut

has app => ;

=attr moniker

The name of the trigger. Multiple configurations for a trigger class
should have different names.

=cut

has moniker => ;

=method install

Called automatically when adding the trigger. Should be overridden to set up
any routes, timers, connections, or other kind of listeners to fire the
configured triggers.

=cut

sub install( $self, $app, $config={} ) {
    $self->app( $app );
}

sub create( $self, $data ) {
    # Created a new trigger
    $data->{class} //= blessed $self;
    $data->{state} //= "inactive";
    # XXX: Auto-encode JSON in Yancy
    $data->{config} = encode_json( $data->{config} // {} );
    $data->{input} = encode_json( $data->{input} // {} );

    return $self->app->yancy->create( zapp_triggers => $data );
}

sub delete( $self, $trigger_id ) {
    return $self->app->yancy->delete( zapp_triggers => $trigger_id );
}

sub set( $self, $trigger_id, $data ) {
    # XXX: Auto-encode JSON in Yancy
    $data->{config} &&= encode_json( $data->{config} );
    $data->{input} &&= encode_json( $data->{input} );
    return $self->app->yancy->set( zapp_triggers => $trigger_id, $data );
}

=method enqueue

Enqueue the plan for the given trigger ID. The plan input will be processed via
L<Zapp::Formula/resolve>, passing in the given C<context> hash reference of data.
Returns the run enqueued (from L<Zapp/enqueue_plan>).

=cut

sub enqueue( $self, $trigger_id, $context ) {
    # Called by the trigger to enqueue a job. Creates a row in
    # zapp_trigger_runs automatically.
    my $trigger = $self->app->yancy->get( zapp_triggers => $trigger_id );

    # Should modify $input from the trigger input to the plan input, if
    # needed.
    my $raw_input = decode_json( $trigger->{input} );
    my %input;
    for my $field ( keys %$raw_input ) {
        my $raw_value = $raw_input->{ $field }{ value };
        $input{ $field } = $self->app->formula->resolve( $raw_value, $context );
    }

    my $run = $self->app->enqueue_plan( $trigger->{plan_id}, \%input );
    $self->app->yancy->create(
        zapp_trigger_runs => {
            trigger_id => $trigger_id,
            run_id => $run->{ run_id },
            context => encode_json( $context ),
        },
    );

    return $run;
}

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

1;

__DATA__
