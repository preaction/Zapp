package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;

sub execute( $self, @args ) {
    # XXX: Interpolate arguments and save to `$self->args`
    # XXX: Does this mean we can't work with existing Minion tasks?

    return $self->SUPER::execute( @args );
}

sub finish( $self, @args ) {
    # XXX: Save result to database

    return $self->SUPER::finish( @args );
}

sub schema( $class ) {
    return {
        args => {
            type => 'array',
        },
        result => {
            type => 'string',
        },
    };
}

1;
