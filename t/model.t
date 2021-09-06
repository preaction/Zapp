
=head1 DESCRIPTION

This tests Zapp::Schema and Zapp::Item classes.

=cut

use Mojo::Base -strict, -signatures;
use Test::Zapp;
use Test::More;
use Mojo::JSON qw( decode_json encode_json );

my $t = Test::Zapp->new;
my $m = $t->app->model;

subtest 'plans' => sub {
    my $plan_id;

    subtest 'create' => sub {
        $plan_id = $m->schema( 'plans' )->create({
            label => 'Deliver Pillows',
            tasks => [
                {
                    name => 'GetPillow',
                    class => 'Zapp::Task::Script',
                    input => {
                        script => 'echo We could be faster with more pillows!',
                    },
                },
            ],
            inputs => [
                {
                    name => 'color',
                    type => 'string',
                    value => 'White',
                },
            ],
        });

        my $plan = $m->backend->get( zapp_plans => $plan_id );
        is $plan->{label}, 'Deliver Pillows', 'plan label is correct';

        my $tasks = $m->backend->list( zapp_plan_tasks => { plan_id => $plan_id }, order_by => 'task_id' );
        is $tasks->{total}, 1, '1 task created';
        is $tasks->{items}[0]{class}, 'Zapp::Task::Script', 'task class is correct';
        is $tasks->{items}[0]{input},
            encode_json({ script => 'echo We could be faster with more pillows!' }),
            'task input is correct';

        my $inputs = $m->backend->list( zapp_plan_inputs => { plan_id => $plan_id }, order_by => 'name' );
        is $inputs->{total}, 1, '1 input created';
        is $inputs->{items}[0]{name}, 'color', 'input name is correct';
        is $inputs->{items}[0]{type}, 'string', 'input type is correct';
        is $inputs->{items}[0]{value}, encode_json('White'), 'input value is correct';
    };

    subtest 'get' => sub {
        my $plan = $m->schema( 'plans' )->get( $plan_id );
        is $plan->{label}, 'Deliver Pillows', 'plan label is correct';

        is ref $plan->{tasks}, 'ARRAY', 'tasks is arrayref';
        is scalar $plan->{tasks}->@*, 1, '1 task returned';
        is $plan->{tasks}[0]{class}, 'Zapp::Task::Script', 'task class is correct';
        is_deeply $plan->{tasks}[0]{input},
            { script => 'echo We could be faster with more pillows!' },
            'task input is correct';

        is ref $plan->{inputs}, 'ARRAY', 'inputs is arrayref';
        is scalar $plan->{inputs}->@*, 1, '1 input returned';
        is $plan->{inputs}[0]{name}, 'color', 'input name is correct';
        is $plan->{inputs}[0]{type}, 'string', 'input type is correct';
        is_deeply $plan->{inputs}[0]{value}, 'White', 'input value is correct';
    };
};

done_testing;
