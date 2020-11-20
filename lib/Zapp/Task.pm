package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;
use Yancy::Util qw( fill_brackets );
use Mojo::JSON qw( decode_json );

sub execute( $self, @args ) {
    my $run_id = $self->app->yancy->get( zapp_run_jobs => $self->id )->{run_id};
    my $run = $self->app->yancy->get( zapp_runs => $run_id );
    my $input = decode_json( $run->{input_values} );

    # Interpolate arguments
    # XXX: Does this mean we can't work with existing Minion tasks?
    $self->args( $self->_interpolate_args( $self->args, $input ) );

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

sub _interpolate_args( $self, $args, $vars ) {
    if ( !ref $args ) {
        return fill_brackets( $args, $vars );
    }
    elsif ( ref $args eq 'ARRAY' ) {
        return [
            map { $self->_interpolate_args( $_, $vars ) }
            $args->@*
        ];
    }
    elsif ( ref $args eq 'HASH' ) {
        return {
            map { $_ => $self->_interpolate_args( $args->{$_}, $vars ) }
            keys $args->%*
        };
    }
    die "Unknown ref type for args: " . ref $args;
}

1;
