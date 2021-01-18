
=head1 DESCRIPTION

This tests the Zapp::Task::Request class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Zapp;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json );

my $mysqld = Test::mysqld->new(
    my_cnf => {
        # Needed for Minion::Backend::mysql
        log_bin_trust_function_creators => 1,
    },
) or plan skip_all => $Test::mysqld::errstr;

my $t = Test::Zapp->new( {
    backend => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
    minion => {
        mysql => { dsn => $mysqld->dsn( dbname => 'test' ) },
    },
} );
$t->app->ua( $t->ua );

# Add some test endpoints
my $last_request;
$t->app->routes->get( '/test/success' )
  ->to( cb => sub( $c ) {
    $last_request = $c->tx->req;
    $c->res->headers->content_type( 'text/plain' );
    $c->render( text => 'Success' );
  } );
$t->app->routes->get( '/test/unauthorized' )
  ->to( cb => sub( $c ) {
    $last_request = $c->tx->req;
    $c->res->headers->content_type( 'text/plain' );
    $c->res->code( 401 );
    $c->render( text => 'You are not authorized' );
  } );

subtest 'run' => sub {
    $t->run_task(
        'Zapp::Task::Request' => {
            method => 'GET',
            url => $t->ua->server->url->path( '/test/success' ),
        },
        'Request: Success',
    );
    $t->task_info_is( state => 'finished' );
    $t->task_output_is({
        res => {
            is_success => 1,
            code => 200,
            message => 'OK',
            body => 'Success',
            headers => {
                content_type => 'text/plain',
            },
        },
    });
};

subtest 'auth' => sub {
    subtest 'bearer' => sub {
        subtest 'success' => sub {
            $t->run_task(
                'Zapp::Task::Request' => {
                    auth => {
                        type => 'bearer',
                        token => 'AUTHBEARERTOKEN',
                    },
                    method => 'GET',
                    url => $t->ua->server->url->path( '/test/success' ),
                },
                'Test: Bearer Auth - Success',
            );
            $t->task_info_is( state => 'finished', 'job finished' );
            $t->task_output_is({
                res => {
                    is_success => 1,
                    code => 200,
                    message => 'OK',
                    body => 'Success',
                    headers => {
                        content_type => 'text/plain',
                    },
                },
            });

            is $last_request->headers->authorization,
                'Bearer AUTHBEARERTOKEN',
                'Authorization HTTP header is correct';
        };

        subtest 'unauthorized' => sub {
            $t->run_task(
                'Zapp::Task::Request' => {
                    auth => {
                        type => 'bearer',
                        token => 'AUTHBEARERTOKEN',
                    },
                    method => 'GET',
                    url => $t->ua->server->url->path( '/test/unauthorized' ),
                },
                'Test: Bearer Auth - Unauthorized',
            );
            $t->task_info_is( state => 'failed', 'job failed' );
            $t->task_output_is({
                res => {
                    is_success => '',
                    code => 401,
                    message => 'Unauthorized',
                    body => 'You are not authorized',
                    headers => {
                        content_type => 'text/plain',
                    },
                },
            });

            is $last_request->headers->authorization,
                'Bearer AUTHBEARERTOKEN',
                'Authorization HTTP header is correct';
        };
    };

};

subtest 'args form' => sub {

    subtest 'defaults' => sub {
        my $plan = $t->app->create_plan( {
            name => '',
            tasks => [
                {
                    name => '',
                    class => 'Zapp::Task::Request',
                    args => encode_json({}),
                },
            ],
        } );

        $t->get_ok( '/plan/' . $plan->{plan_id} )
            ->status_is( 200 )
            ->element_exists(
                '[name="task[0].args.method"]',
                'method input exists',
            )
            ->attr_is(
                '[name="task[0].args.method"] [selected]',
                value => 'GET',
                'GET method selected by default',
            )
            ->element_exists(
                '[name="task[0].args.url"]',
                'url input exists',
            )
            ->attr_is(
                '[name="task[0].args.url"]',
                value => '',
                'url correct value',
            )
            ->element_exists(
                '[name="task[0].args.auth.type"]',
                'auth type input exists',
            )
            ->attr_is(
                '[name="task[0].args.auth.type"] [selected]',
                value => '',
                'auth type correct option selected',
            )
            ->element_exists(
                '[name="task[0].args.auth.token"]',
                'auth token input exists',
            )
            ->element_exists_not(
                '.zapp-visible [name="task[0].args.auth.token"]',
                'auth token input is not visible',
            )
            ;
    };

    subtest 'with bearer auth' => sub {
        my $plan = $t->app->create_plan( {
            name => '',
            tasks => [
                {
                    name => '',
                    class => 'Zapp::Task::Request',
                    args => encode_json({
                        method => 'POST',
                        url => '/foo/bar',
                        auth => {
                            type => 'bearer',
                            token => 'AUTHTOKEN',
                        },
                    }),
                },
            ],
        } );

        $t->get_ok( '/plan/' . $plan->{plan_id} )
            ->status_is( 200 )
            ->element_exists(
                '[name="task[0].args.method"]',
                'method input exists',
            )
            ->attr_is(
                '[name="task[0].args.method"] [selected]',
                value => 'POST',
                'method correct option selected',
            )
            ->element_exists(
                '[name="task[0].args.url"]',
                'url input exists',
            )
            ->attr_is(
                '[name="task[0].args.url"]',
                value => '/foo/bar',
                'url correct value',
            )
            ->element_exists(
                '[name="task[0].args.auth.type"]',
                'auth type input exists',
            )
            ->attr_is(
                '[name="task[0].args.auth.type"] [selected]',
                value => 'bearer',
                'auth type correct option selected',
            )
            ->element_exists(
                '[name="task[0].args.auth.token"]',
                'auth token input exists',
            )
            ->element_exists(
                '.zapp-visible [name="task[0].args.auth.token"]',
                'auth token input is visible',
            )
            ->attr_is(
                '[name="task[0].args.auth.token"]',
                value => 'AUTHTOKEN',
                'auth token input value is correct',
            )
            ;
    };

};

done_testing;

