package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Util qw( get_path_from_data );

sub execute( $self, @args ) {
    my $run_job = $self->app->yancy->get( zapp_run_jobs => $self->id );
    my $context = decode_json( $run_job->{context} );

    # Interpolate arguments
    # XXX: Does this mean we can't work with existing Minion tasks?
    $self->args( $self->_interpolate_args( $self->args, $context ) );

    return $self->SUPER::execute( @args );
}

sub finish( $self, $result=undef ) {
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

    # Save assignments to child contexts
    my $task = $self->app->yancy->get( zapp_plan_tasks => $task_id );
    my $result_saves = decode_json( $task->{results} // '[]' );
    my $context = decode_json( $run_job->{context} // '{}' );
    for my $save ( @$result_saves ) {
        $context->{ $save->{name} } = get_path_from_data( $save->{expr}, $result );
    }
    for my $minion_job_id ( @{ $self->info->{children} } ) {
        $self->app->yancy->backend->set(
            zapp_run_jobs => $minion_job_id => {
                context => encode_json( $context ),
            },
        );
    }

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
        return scalar $args =~ s{(?<!\\)\{([^\s\}]+)\}}{$vars->{$1}}reg
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
