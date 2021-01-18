package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Util qw( get_path_from_data fill_input );

sub execute( $self, @args ) {
    my $run_job = $self->app->yancy->get( zapp_run_jobs => $self->id );
    my $context = decode_json( $run_job->{context} );

    # Interpolate arguments
    # XXX: Does this mean we can't work with existing Minion tasks?
    $self->args( fill_input( $context, $self->args ) );

    return $self->SUPER::execute( @args );
}

sub finish( $self, $output=undef ) {
    my $run_job = $self->app->yancy->get( zapp_run_jobs => $self->id );
    my ( $run_id, $task_id ) = $run_job->@{qw( run_id task_id )};

    # Verify tests
    my @tests = $self->app->yancy->list( zapp_run_tests => { run_id => $run_id, task_id => $task_id }, { order_by => 'test_id' } );
    for my $test ( @tests ) {
        my $expr_value = $test->{ expr_value } = $output->{ $test->{expr} }; # XXX Support ./[0] syntax (or JSONPath instead?)
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
            return $self->fail( $output );
        }
    }

    # Save assignments to child contexts
    my $task = $self->app->yancy->get( zapp_plan_tasks => $task_id );
    my $output_saves = decode_json( $task->{output} // '[]' );
    my $context = decode_json( $run_job->{context} // '{}' );
    for my $save ( @$output_saves ) {
        $context->{ $save->{name} } = get_path_from_data( $save->{expr}, $output );
    }
    for my $minion_job_id ( @{ $self->info->{children} } ) {
        $self->app->yancy->backend->set(
            zapp_run_jobs => $minion_job_id => {
                context => encode_json( $context ),
            },
        );
    }

    return $self->SUPER::finish( $output );
}

sub schema( $class ) {
    return {
        input => {
            type => 'array',
        },
        output => {
            type => 'string',
        },
    };
}

1;
