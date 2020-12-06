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

sub finish( $self, $result ) {
    my $run_job = $self->app->yancy->get( zapp_run_jobs => $self->id );
    my ( $run_id, $task_id ) = $run_job->@{qw( run_id task_id )};

    # Verify tests
    my @tests = $self->app->yancy->list( zapp_run_tests => { run_id => $run_id, task_id => $task_id }, { order_by => 'test_id' } );
    for my $test ( @tests ) {
        my $expr_value = $test->{ expr_value } = $result->{ $test->{expr} }; # XXX Support ./[0] syntax (or JSONPath instead?)
        my $pass;
        if ( $test->{op} eq '==' ) {
            $pass = ( $expr_value eq $test->{value} );
        }
        elsif ( $test->{op} eq '!=' ) {
            $pass = ( $expr_value ne $test->{value} );
        }
        elsif ( $test->{op} eq '>' ) {
            $pass = ( $expr_value gt $test->{value} );
        }
        elsif ( $test->{op} eq '<' ) {
            $pass = ( $expr_value lt $test->{value} );
        }
        elsif ( $test->{op} eq '>=' ) {
            $pass = ( $expr_value ge $test->{value} );
        }
        elsif ( $test->{op} eq '<=' ) {
            $pass = ( $expr_value le $test->{value} );
        }
        $test->{pass} = $pass;

        my $rows = $self->app->yancy->backend->set(
            zapp_run_tests =>
            { $test->%{qw( run_id test_id )} },
            {
                expr_value => $test->{expr_value},
                pass => $test->{pass},
            },
        );
        if ( !$pass ) {
            return $self->fail( $result );
        }
    }

    # XXX: Save assignments to input
    return $self->SUPER::finish( $result );
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
