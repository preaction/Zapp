
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
$t->app->routes->get( '/test/success' )
  ->to( cb => sub( $c ) {
    $c->res->headers->content_type( 'text/plain' );
    $c->render( text => 'Success' );
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
    $t->task_result_is({
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

done_testing;

