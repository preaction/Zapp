package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Util qw( get_path_from_data get_path_from_schema fill_input );

sub execute( $self, @args ) {
    my $run_job = $self->app->yancy->get( zapp_run_jobs => $self->id );
    my $context = decode_json( $run_job->{context} );
    ; $self->app->log->debug( "Got context: " . $self->app->dumper( $context ) );
    my %values;
    for my $name ( keys %$context ) {
        my $input = $context->{ $name };
        my $type = $self->app->zapp->types->{ $input->{type} }
            or die qq{Could not find type "$input->{type}"};
        $values{ $name } = $type->task_input( { run_id => $run_job->{run_id} }, { task_id => $run_job->{task_id} }, $input->{value} );
    }

    # Interpolate arguments
    # XXX: Does this mean we can't work with existing Minion tasks?
    $self->args( fill_input( \%values, $self->args ) );

    return $self->SUPER::execute( @args );
}

sub finish( $self, $output=undef ) {
    return $self->SUPER::finish if !defined $output; # XXX: Minion calls this again after we do inside the task?
    my $run_job = $self->app->yancy->get( zapp_run_jobs => $self->id );
    my ( $run_id, $task_id ) = $run_job->@{qw( run_id task_id )};

    # Verify tests
    ; $self->app->log->info( 'Running tests' );
    my @tests = $self->app->yancy->list( zapp_run_tests => { run_id => $run_id, task_id => $task_id }, { order_by => 'test_id' } );
    for my $test ( @tests ) {
        # Stringify whatever data we get because the value to test
        # against can only ever be a string.
        # XXX: Support JSON comparisons?
        my $expr_value = $test->{ expr_value } = "".get_path_from_data( $test->{expr}, $output );
        # XXX: Add good, robust logging to help debug job problems
        #; $self->app->log->debug( sprintf 'Test expr %s has value %s (%s %s)', $test->@{qw( expr expr_value op value )} );
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
            $self->app->log->debug(
                sprintf "Run %s failed test %s %s %s with value %s",
                    $test->@{qw( run_id expr op value expr_value )},
            );
            return $self->fail( $output );
        }
    }

    ; $self->app->log->info( 'Saving context' );
    # Save assignments to child contexts
    my $task = $self->app->yancy->get( zapp_plan_tasks => $task_id );
    my $output_saves = decode_json( $task->{output} // '[]' );
    my $context = decode_json( $run_job->{context} // '{}' );
    for my $save ( @$output_saves ) {
        ; $self->app->log->debug( "Saving: " . $self->app->dumper( $save ) );
        my $schema = get_path_from_schema( $save->{expr}, $self->schema->{output} );
        my $type_name = $save->{type} || $schema->{type};
        my $type = $self->app->zapp->types->{ $type_name }
            or die "Could not find type name $type_name";
        my $value = get_path_from_data( $save->{expr}, $output );
        ; $self->app->log->debug( "Got schema: " . $self->app->dumper( $schema ) );

        $context->{ $save->{name} } = {
            value => $type->task_output( { run_id => $run_id }, { task_id => $task_id }, $value ),
            type => $type_name,
        };
    }
    $self->app->log->debug( "Saving context: " . $self->app->dumper( $context ) );
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
