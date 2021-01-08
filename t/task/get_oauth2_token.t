
=head1 DESCRIPTION

This tests the Zapp::Task::GetOAuth2Token class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Mojo;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json false true );
use Mojo::Util qw( b64_decode );

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

my $last_request;
# Add some test endpoints
$t->app->routes->post( '/test/success' )
  ->to( cb => sub( $c ) {
    # XXX: HTTP Basic auth: base64( url_encode( <client_id> ) . ':' . url_encode( <client_secret> ) )
    # XXX: $c->param( 'client_id' ); $c->param( 'client_secret' );
    $last_request = $c->tx->req;
    return $c->render(
        status => 200,
        json => {
            access_token => 'TESTACCESSTOKEN',
            token_type => 'bearer',
            expires_in => 3600,
            scope => $c->param( 'scope' ),
        },
    );
  } );
$t->app->routes->post( '/test/failure' )
  ->to( cb => sub( $c ) {
    $last_request = $c->tx->req;
    return $c->render(
        status => 400,
        json => {
            error => 'invalid_scope',
            error_description => 'You gave an invalid scope.',
        },
    );
  } );

subtest 'run' => sub {
    subtest 'success' => sub {
        my $plan = $t->app->create_plan({
            name => 'Test: Success',
            tasks => [
                {
                    name => '',
                    class => 'Zapp::Task::GetOAuth2Token',
                    args => encode_json({
                        endpoint => $t->ua->server->url->path( '/test/success' )->to_abs,
                        scope => 'create',
                        client_id => '<client_id>',
                        client_secret => '<client_secret>',
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
                is_success => true,
                access_token => 'TESTACCESSTOKEN',
                token_type => 'bearer',
                expires_in => 3600,
                scope => 'create',
                refresh_token => undef,
            },
            'result data is correct'
                or diag explain $job->info->{result};

        ok $last_request, 'mock token request handler called';
        is $last_request->param( 'scope' ), 'create',
            'scope passed in query param';
        is $last_request->param( 'grant_type' ), 'client_credentials',
            'grant_type passed in query param';

        my ( $auth ) = $last_request->headers->authorization =~ m{Basic (\S+)};
        my ( $got_client_id, $got_client_secret ) = split /:/, b64_decode( $auth );
        is $got_client_id, '<client_id>',
            'client_id is "username" in HTTP Authorization header';
        is $got_client_secret, '<client_secret>',
            'client_secret is "password" in HTTP Authorization header';
    };

    subtest 'failure' => sub {
        my $plan = $t->app->create_plan({
            name => 'Test: Failure',
            tasks => [
                {
                    name => '',
                    class => 'Zapp::Task::GetOAuth2Token',
                    args => encode_json({
                        endpoint => $t->ua->server->url->path( '/test/failure' ),
                        scope => 'create',
                        client_id => '<client_id>',
                        client_secret => '<client_secret>',
                    }),
                },
            ],
        });
        my $run = $t->app->enqueue( $plan->{plan_id}, {} );

        my $worker = $t->app->minion->worker->register;
        my $job = $worker->dequeue;
        my $e = $job->execute;
        ok !$e, 'job executed successfully' or diag "Job error: ", explain $e;

        is $job->info->{state}, 'failed', 'job failed';
        is_deeply $job->info->{result},
            {
                is_success => false,
                error => 'invalid_scope',
                error_description => 'You gave an invalid scope.',
                error_uri => undef,
            },
            'result data is correct'
                or diag explain $job->info->{result};

        ok $last_request, 'mock token request handler called';
        is $last_request->param( 'scope' ), 'create',
            'scope passed in query param';
        is $last_request->param( 'grant_type' ), 'client_credentials',
            'grant_type passed in query param';

        my ( $auth ) = $last_request->headers->authorization =~ m{Basic (\S+)};
        my ( $got_client_id, $got_client_secret ) = split /:/, b64_decode( $auth );
        is $got_client_id, '<client_id>',
            'client_id is "username" in HTTP Authorization header';
        is $got_client_secret, '<client_secret>',
            'client_secret is "password" in HTTP Authorization header';
    };
};

done_testing;

