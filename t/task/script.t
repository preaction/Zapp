
=head1 DESCRIPTION

This tests the Zapp::Task::Script class.

=cut

use Mojo::Base -strict, -signatures;
use Test::Zapp;
use Test::More;
use Test::mysqld;
use Mojo::JSON qw( decode_json encode_json false true );
use Zapp::Task::Script;

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

subtest 'run' => sub {
    subtest 'with shell' => sub {
        subtest 'success' => sub {
            $t->run_task(
                'Zapp::Task::Script' => {
                    script => qq{echo Hello, World},
                },
                'Test: Success',
            );
            $t->task_info_is( state => 'finished', 'job finished' );
            $t->task_output_like( pid => qr{\d+}, 'pid is saved' );
            $t->task_output_is( exit => 0, 'exit is correct' );
            $t->task_output_is( output => "Hello, World\n", 'output is correct' );
            $t->task_output_is( info => 'Script exited with value: 0', 'info is correct' );
        };

        subtest 'failure' => sub {
            $t->run_task(
                'Zapp::Task::Script' => {
                    script => qq{echo Oh no!; exit 1},
                },
                'Test: Failure',
            );
            $t->task_info_is( state => 'failed', 'job failed' );
            $t->task_output_like( pid => qr{\d+}, 'pid is saved' );
            $t->task_output_is( exit => 1, 'exit is correct' );
            $t->task_output_is( output => "Oh no!\n", 'output is correct' );
            $t->task_output_is( info => 'Script exited with value: 1', 'info is correct' );
        };
    };

    subtest 'with shebang' => sub {
        subtest 'success' => sub {
            $t->run_task(
                'Zapp::Task::Script' => {
                    script => qq{#!$^X\nprint "Hello, World\\n";\n exit 0;\n},
                },
                'Test: Success',
            );
            $t->task_info_is( state => 'finished', 'job finished' );
            $t->task_output_like( pid => qr{\d+}, 'pid is saved' );
            $t->task_output_is( exit => 0, 'exit is correct' );
            $t->task_output_is( output => "Hello, World\n", 'output is correct' );
            $t->task_output_is( info => 'Script exited with value: 0', 'info is correct' );
        };

        subtest 'failure' => sub {
            $t->run_task(
                'Zapp::Task::Script' => {
                    script => qq{#!$^X\nprint "Oh no!\\n";\n exit 1;\n},
                },
                'Test: Failure',
            );
            $t->task_info_is( state => 'failed', 'job failed' );
            $t->task_output_like( pid => qr{\d+}, 'pid is saved' );
            $t->task_output_is( exit => 1, 'exit is correct' );
            $t->task_output_is( output => "Oh no!\n", 'output is correct' );
            $t->task_output_is( info => 'Script exited with value: 1', 'info is correct' );
        };
    };
};


done_testing;
