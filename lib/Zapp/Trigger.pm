package Zapp::Trigger;
# ABSTRACT: Trigger a plan from an event

use Mojo::Base -base, -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Scalar::Util qw( blessed );
use Mojo::Loader qw( data_section );

has app => ;
has moniker => ;

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
