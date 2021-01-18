package Test::Zapp;

use Mojo::Base 'Test::Mojo';
use Mojo::JSON qw( encode_json );
use Scalar::Util qw( blessed );
use Test::More;

sub new {
    my $class = shift;
    # Test Zapp itself by default
    if ( ref $_[0] && !blessed $_[0] ) {
        unshift @_, 'Zapp';
    }
    return $class->SUPER::new( @_ );
}

sub run_queue {
    my ( $self ) = @_;
    # Run all tasks on the queue
    my $worker = $self->app->minion->worker->register;
    while ( my $job = $worker->dequeue ) {
        my $e = $job->execute;
        $self->test( 'ok', !$e, 'job executed successfully' );
        $self->or( sub { diag "Job error: ", explain $e } );
    }
    $worker->unregister;
}

sub run_task {
    my ( $self, $task_class, $input, $name ) = @_;
    my $plan = $self->{zapp}{plan} = $self->app->create_plan({
        name => $name // $task_class,
        tasks => [
            {
                name => $task_class,
                class => $task_class,
                input => encode_json( $input ),
            },
        ],
    });
    my $run = $self->{zapp}{run} = $self->app->enqueue( $plan->{plan_id}, {} );

    my $worker = $self->app->minion->worker->register;
    my $job = $self->{zapp}{job} = $worker->dequeue;
    my $e = $job->execute;
    $self->test( 'ok', !$e, 'job executed successfully' );
    $self->or( sub { diag "Job error: ", explain $e } );
    $worker->unregister;
    return $self;
}

sub task_output_is {
    my ( $self, $output, $name ) = @_;
    $self->test( 'is_deeply', $self->{zapp}{job}->info->{result}, $output, $name );
}

sub task_info_is {
    my ( $self, $info_key, $info_value, $name ) = @_;
    $self->test( 'is', $self->{zapp}{job}->info->{$info_key}, $info_value, $name );
}

1;

