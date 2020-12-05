
=head1 DESCRIPTION

This tests the base Zapp::Task class.

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

subtest 'execute' => sub {
    my $plan = $t->app->create_plan({
        name => 'Deliver a package',
        description => 'To a dangerous place',
        tasks => [
            {
                name => 'Plan trip',
                class => 'Zapp::Task::Echo',
                args => encode_json({
                    destination => '{destination}',
                }),
                tests => [
                    {
                        expr => 'destination',
                        op => '!=',
                        value => '',
                    },
                ],
            },
            {
                name => 'Deliver package',
                class => 'Zapp::Task::Echo',
                args => encode_json({
                    delivery_address => 'Certain Doom on {destination}',
                }),
            },
        ],
        inputs => [
            {
                name => 'destination',
                type => 'string',
                description => 'Where to send the crew to their doom',
                default_value => encode_json( 'Chapek 9' ),
            },
        ],
    });

    my $input = {
        destination => 'Nude Beach Planet',
    };

    my $run = $t->app->enqueue( $plan->{plan_id}, $input );

    # Check job results
    my $job = $t->app->minion->job( $run->{jobs}[0] );
    my $e = $job->execute;
    ok !$e, 'job executed successfully' or diag "Job error: $e";
    is_deeply $job->args,
        [ {
            destination => 'Nude Beach Planet',
        } ],
        'job args are interpolated with input';

    $job = $t->app->minion->job( $run->{jobs}[1] );
    $e = $job->execute;
    ok !$e, 'job executed successfully' or diag "Job error: $e";
    is_deeply $job->args,
        [ {
            delivery_address => 'Certain Doom on Nude Beach Planet',
        } ],
        'job args are interpolated with input';

};

done_testing;

