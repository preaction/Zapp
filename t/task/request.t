
=head1 DESCRIPTION

This tests the Zapp::Task::Request class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Mojo;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json );

my $mysqld = Test::mysqld->new(
    my_cnf => {
        # Needed for Minion::Backend::mysql
        log_bin_trust_function_creators => 1,
    },
) or plan skip_all => $Test::mysqld::errstr;

my $t = Test::Mojo->new( 'Zapp', {
    backend => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
    minion => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
} );
$t->app->ua( $t->ua );

# Add some test endpoints
$t->app->routes->get( '/test/success' )
  ->to( cb => sub( $c ) {
    $c->res->headers->content_type( 'text/plain' );
    $c->render( text => 'Success' );
  } );

subtest 'run' => sub {
    my $plan = $t->app->create_plan({
        name => 'Test: Success',
        tasks => [
            {
                name => '',
                class => 'Zapp::Task::Request',
                args => encode_json({
                    method => 'GET',
                    url => $t->ua->server->url->path( '/test/success' ),
                }),
            },
        ],
    });
    my $run = $t->app->enqueue( $plan->{plan_id}, {} );

    my $worker = $t->app->minion->worker->register;
    my $job = $worker->dequeue;
    my $e = $job->execute;
    ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;

    is $job->info->{state}, 'finished', 'job finished';
    is_deeply $job->info->{result},
        {
            res => {
                is_success => 1,
                code => 200,
                message => 'OK',
                body => 'Success',
                headers => {
                    content_type => 'text/plain',
                },
            },
        },
        'result data is correct'
            or diag explain $job->info->{result};
};

done_testing;

