
=head1 DESCRIPTION

This tests all types can be used in creating plans, running plans, and
viewing runs. This tests all base types as created in Zapp by default,
as well as some examples of types that require configuration like
L<Zapp::Type::Enum>.

=cut

use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Zapp;
use Zapp::Type::Enum;
use Mojo::File qw( tempdir tempfile );
use Mojo::JSON qw( encode_json decode_json );
use Zapp::Util qw( get_path_from_data get_path_from_schema );

my $t = Test::Zapp->new( 'Zapp' );

# Dir to store files for Zapp::Type::File
my $temp = tempdir();
my $uploads_dir = $temp->child( 'uploads' )->make_path;
$t->app->home( $temp );
my $file_value = $uploads_dir->child( 'file.txt' )->spurt( 'File content' )->to_rel( $uploads_dir );

# Types that require configuration to use
my %added_types = (
    enum => Zapp::Type::Enum->new( [qw( Scruffy Katrina Xanthor )] ),
);
$t->app->zapp->add_type( $_ => $added_types{ $_ } ) for keys %added_types;

# Create a plan with input of every type
my %plan_data = (
    name => 'Test Plan',
    # XXX: Allow user ordering for inputs
    inputs => [
        {
            name => 'boolean',
            type => 'boolean',
            default_value => encode_json( 1 ),
        },
        {
            name => 'enum',
            type => 'enum',
            default_value => encode_json( 'Scruffy' ),
        },
        {
            name => 'file',
            type => 'file',
            default_value => encode_json( "$file_value" ),
        },
        {
            name => 'integer',
            type => 'integer',
            default_value => encode_json( 56 ),
        },
        {
            name => 'number',
            type => 'number',
            default_value => encode_json( 1.234 ),
        },
        {
            name => 'string',
            type => 'string',
            default_value => encode_json( 'string' ),
        },
    ],
);

subtest 'plan input' => sub {
    subtest 'plan edit form' => sub {
        my $plan = $t->app->create_plan({%plan_data});
        $t->get_ok( '/plan/' . $plan->{plan_id} )->status_is( 200 );

        subtest 'input 0 - boolean' => sub {
            $t->element_exists( 'form [name="input[0].default_value"]' )
              ->attr_is( 'form [name="input[0].default_value"]', type => 'text' )
              ->attr_is( 'form [name="input[0].default_value"]', value => 1 )
              ->attr_is( 'form [name="input[0].type"]', value => 'boolean' )
              ->attr_is( 'form [name="input[0].name"]', value => 'boolean' )
        };

        subtest 'input 1 - enum' => sub {
            $t->element_exists( 'form [name="input[1].default_value"]' )
              ->element_exists( 'form select[name="input[1].default_value"]', 'tag is <select>' )
              ->attr_is( 'form [name="input[1].default_value"] [selected]', value => 'Scruffy' )
              ->attr_is( 'form [name="input[1].type"]', value => 'enum' )
              ->attr_is( 'form [name="input[1].name"]', value => 'enum' )
        };

        subtest 'input 2 - file' => sub {
            $t->element_exists( 'form [name="input[2].default_value"]' )
              ->attr_is( 'form [name="input[2].default_value"]', type => 'file' )
              ->attr_is( 'form [name="input[2].default_value"]', value => $file_value->basename )
              ->attr_is( 'form [name="input[2].type"]', value => 'file' )
              ->attr_is( 'form [name="input[2].name"]', value => 'file' )
        };

        subtest 'input 3 - number' => sub {
            $t->element_exists( 'form [name="input[3].default_value"]' )
              ->attr_is( 'form [name="input[3].default_value"]', type => 'text' )
              ->attr_is( 'form [name="input[3].default_value"]', value => '56' )
              ->attr_is( 'form [name="input[3].type"]', value => 'integer' )
              ->attr_is( 'form [name="input[3].name"]', value => 'integer' )
        };

        subtest 'input 4 - number' => sub {
            $t->element_exists( 'form [name="input[4].default_value"]' )
              ->attr_is( 'form [name="input[4].default_value"]', type => 'text' )
              ->attr_is( 'form [name="input[4].default_value"]', value => '1.234' )
              ->attr_is( 'form [name="input[4].type"]', value => 'number' )
              ->attr_is( 'form [name="input[4].name"]', value => 'number' )
        };

        subtest 'input 5 - string' => sub {
            $t->element_exists( 'form [name="input[5].default_value"]' )
              ->attr_is( 'form [name="input[5].default_value"]', type => 'text' )
              ->attr_is( 'form [name="input[5].default_value"]', value => 'string' )
              ->attr_is( 'form [name="input[5].type"]', value => 'string' )
              ->attr_is( 'form [name="input[5].name"]', value => 'string' )
        };
    };

    subtest 'save plan' => sub {
        my $plan = $t->app->create_plan({%plan_data});
        $t->post_ok( '/plan/' . $plan->{plan_id}, form => {
            %plan_data{qw( name )},

            'input[0].name' => 'boolean',
            'input[0].type' => 'boolean',
            'input[0].default_value' => 0,

            'input[1].name' => 'integer',
            'input[1].type' => 'integer',
            'input[1].default_value' => 67,

            'input[2].name' => 'enum',
            'input[2].type' => 'enum',
            'input[2].default_value' => 'Katrina',

            'input[3].name' => 'file',
            'input[3].type' => 'file',
            'input[3].default_value' => {
                content => 'New File',
                filename => 'file.txt',
            },

            'input[4].name' => 'number',
            'input[4].type' => 'number',
            'input[4].default_value' => 2.345,

            'input[5].name' => 'string',
            'input[5].type' => 'string',
            'input[5].default_value' => 'new string',

        } )->status_is( 302 );

        my @inputs = $t->app->yancy->list( zapp_plan_inputs => { plan_id => $plan->{plan_id} } );

        subtest 'input 0 - boolean' => sub {
            is decode_json( $inputs[0]{default_value} ), 0;
        };

        subtest 'input 1 - enum' => sub {
            is decode_json( $inputs[1]{default_value} ), 'Katrina';
        };

        subtest 'input 2 - file' => sub {
            is decode_json( $inputs[2]{default_value} ),
                "plan/$plan->{plan_id}/input/3/file.txt";
            my $file = $t->app->home->child( 'uploads', decode_json( $inputs[2]{default_value} ) );
            ok -e $file, 'file exists';
            is $file->slurp, 'New File', 'file content correct';
        };

        subtest 'input 3 - integer' => sub {
            is decode_json( $inputs[3]{default_value} ), 67;
        };

        subtest 'input 4 - number' => sub {
            is decode_json( $inputs[4]{default_value} ), 2.345;
        };

        subtest 'input 5 - string' => sub {
            is decode_json( $inputs[5]{default_value} ), 'new string';
        };
    };

    subtest 'run form' => sub {
        my $plan = $t->app->create_plan({%plan_data});
        $t->get_ok( '/plan/' . $plan->{plan_id} . '/run' )->status_is( 200 );

        subtest 'input 0 - boolean' => sub {
            $t->element_exists( 'form [name="input[0].value"]' )
              ->attr_is( 'form [name="input[0].value"]', type => 'text' )
              ->attr_is( 'form [name="input[0].value"]', value => 1 )
              ->attr_is( 'form [name="input[0].type"]', value => 'boolean' )
              ->attr_is( 'form [name="input[0].name"]', value => 'boolean' )
        };

        subtest 'input 1 - enum' => sub {
            $t->element_exists( 'form [name="input[1].value"]' )
              ->element_exists( 'form select[name="input[1].value"]', 'tag is <select>' )
              ->attr_is( 'form [name="input[1].value"] [selected]', value => 'Scruffy' )
              ->attr_is( 'form [name="input[1].type"]', value => 'enum' )
              ->attr_is( 'form [name="input[1].name"]', value => 'enum' )
        };

        subtest 'input 2 - file' => sub {
            $t->element_exists( 'form [name="input[2].value"]' )
              ->attr_is( 'form [name="input[2].value"]', type => 'file' )
              ->attr_is( 'form [name="input[2].value"]', value => $file_value->basename )
              ->attr_is( 'form [name="input[2].type"]', value => 'file' )
              ->attr_is( 'form [name="input[2].name"]', value => 'file' )
        };

        subtest 'input 3 - number' => sub {
            $t->element_exists( 'form [name="input[3].value"]' )
              ->attr_is( 'form [name="input[3].value"]', type => 'text' )
              ->attr_is( 'form [name="input[3].value"]', value => '56' )
              ->attr_is( 'form [name="input[3].type"]', value => 'integer' )
              ->attr_is( 'form [name="input[3].name"]', value => 'integer' )
        };

        subtest 'input 4 - number' => sub {
            $t->element_exists( 'form [name="input[4].value"]' )
              ->attr_is( 'form [name="input[4].value"]', type => 'text' )
              ->attr_is( 'form [name="input[4].value"]', value => '1.234' )
              ->attr_is( 'form [name="input[4].type"]', value => 'number' )
              ->attr_is( 'form [name="input[4].name"]', value => 'number' )
        };

        subtest 'input 5 - string' => sub {
            $t->element_exists( 'form [name="input[5].value"]' )
              ->attr_is( 'form [name="input[5].value"]', type => 'text' )
              ->attr_is( 'form [name="input[5].value"]', value => 'string' )
              ->attr_is( 'form [name="input[5].type"]', value => 'string' )
              ->attr_is( 'form [name="input[5].name"]', value => 'string' )
        };
    };

    subtest 'save run' => sub {
        my $plan = $t->app->create_plan({%plan_data});
        $t->post_ok( '/plan/' . $plan->{plan_id} . '/run', form => {
            'input[0].name' => 'boolean',
            'input[0].type' => 'boolean',
            'input[0].value' => 1,

            'input[1].name' => 'enum',
            'input[1].type' => 'enum',
            'input[1].value' => 'Xanthor',

            'input[2].name' => 'file',
            'input[2].type' => 'file',
            'input[2].value' => {
                content => 'Run File',
                filename => 'file.txt',
            },

            'input[3].name' => 'integer',
            'input[3].type' => 'integer',
            'input[3].value' => 89,

            'input[4].name' => 'number',
            'input[4].type' => 'number',
            'input[4].value' => 3.456,

            'input[5].name' => 'string',
            'input[5].type' => 'string',
            'input[5].value' => 'run string',
        } )->status_is( 302 );

        my ( $run_id ) = $t->tx->res->headers->location =~ m{/run/(\d+)};

        my $run = $t->app->yancy->get( zapp_runs => $run_id );
        my $input = decode_json( $run->{input_values} );

        subtest 'input 0 - boolean' => sub {
            is $input->{boolean}{value}, 1;
        };

        subtest 'input 1 - enum' => sub {
            is $input->{enum}{value}, 'Xanthor';
        };

        subtest 'input 2 - file' => sub {
            like $input->{file}{value}, qr{run/\d+/input/2/file\.txt};
            my $file = $t->app->home->child( 'uploads', $input->{file}{value} );
            ok -e $file, 'file exists';
            is $file->slurp, 'Run File', 'file content correct';
        };

        subtest 'input 3 - integer' => sub {
            is $input->{integer}{value}, 89;
        };

        subtest 'input 4 - number' => sub {
            is $input->{number}{value}, 3.456;
        };

        subtest 'input 5 - string' => sub {
            is $input->{string}{value}, 'run string';
        };
    };
};

subtest 'task input/output' => sub {
    # Create a plan with two Script tasks for each type.
    # One handles an input of that type. One provides an output
    # of that type.
    my $plan = $t->app->create_plan({
        name => 'Task I/O Plan',
        tasks => [
            {
                name => 'string: input',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n {{string}}',
                }),
            },
            {
                name => 'string: output',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n Output string',
                }),
                output => encode_json([
                    { name => 'string_output', type => 'string', expr => 'output' },
                ]),
            },

            {
                name => 'integer: input',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n {{integer}}',
                }),
            },
            {
                name => 'integer: output',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n 6543',
                }),
                output => encode_json([
                    { name => 'integer_output', type => 'integer', expr => 'output' },
                ]),
            },

            {
                name => 'number: input',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n {{number}}',
                }),
            },
            {
                name => 'number: output',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n 9.876',
                }),
                output => encode_json([
                    { name => 'number_output', type => 'number', expr => 'output' },
                ]),
            },

            {
                name => 'boolean: input',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n {{boolean}}',
                }),
            },
            {
                name => 'boolean: output',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n 1',
                }),
                output => encode_json([
                    { name => 'boolean_output', type => 'boolean', expr => 'output' },
                ]),
            },

            {
                name => 'file: input',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'cat {{file}}',
                }),
            },
            {
                name => 'file: output',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo File output > /tmp/zapp; echo -n /tmp/zapp',
                }),
                output => encode_json([
                    { name => 'file_output', type => 'file', expr => 'output' },
                ]),
            },

            {
                name => 'enum: input',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n {{enum}}',
                }),
            },
            {
                name => 'enum: output',
                class => 'Zapp::Task::Script',
                input => encode_json({
                    script => 'echo -n Katrina',
                }),
                output => encode_json([
                    { name => 'enum_output', type => 'enum', expr => 'output' },
                ]),
            },
        ],
    });

    my $file = $uploads_dir->child( 'zapp' )->spurt( 'File content' );

    # Run each task in the plan and validate result input/output
    my $input = {
        string => {
            type => 'string',
            value => 'String input',
        },
        integer => {
            type => 'integer',
            value => 1234,
        },
        number => {
            type => 'number',
            value => 5.678,
        },
        boolean => {
            type => 'boolean',
            value => 1,
        },
        file => {
            type => 'file',
            value => $file->to_rel( $uploads_dir ),
        },
        enum => {
            type => 'enum',
            value => 'Scruffy',
        },
    };
    my $run = $t->app->enqueue( $plan->{plan_id}, $input );
    $t->run_queue;

    # The context isn't created after the last job runs, so we have to
    # create it ourselves...
    # XXX: zapp_run_jobs could store both input and output contexts, or
    # just output, with the next job merging input from all parents'
    # output (or from run input, if no parent)
    my $last_job = $t->app->yancy->get( zapp_run_jobs => $run->{jobs}[-1] );
    my $output = $t->app->minion->job( $run->{jobs}[-1] )->info->{result};
    my $task = $t->app->yancy->get( zapp_plan_tasks => $last_job->{task_id} );
    my $output_saves = decode_json( $task->{output} // '[]' );
    my $context = decode_json( $last_job->{context} );
    for my $save ( @$output_saves ) {
        my $type_name = $save->{type};
        my $type = $t->app->zapp->types->{ $type_name }
            or die "Could not find type name $type_name";
        my $value = get_path_from_data( $save->{expr}, $output );
        $context->{ $save->{name} } = {
            value => $type->task_output( $run, $task, $value ),
            type => $type_name,
        };
    }

    subtest 'string: input' => sub {
        my $job = $t->app->minion->job( $run->{jobs}[0] );
        my $result = $job->info->{result};
        is $result->{output}, $input->{string}{value}, 'string input correct';
    };
    subtest 'string: output' => sub {
        is $context->{string_output}{value}, 'Output string', 'string output correct';
    };

    subtest 'integer: input' => sub {
        my $job = $t->app->minion->job( $run->{jobs}[2] );
        my $result = $job->info->{result};
        is $result->{output}, $input->{integer}{value}, 'integer input correct';
    };
    subtest 'integer: output' => sub {
        is $context->{integer_output}{value}, '6543', 'integer output correct';
    };

    subtest 'number: input' => sub {
        my $job = $t->app->minion->job( $run->{jobs}[4] );
        my $result = $job->info->{result};
        is $result->{output}, $input->{number}{value}, 'number input correct';
    };
    subtest 'number: output' => sub {
        is $context->{number_output}{value}, '9.876', 'number output correct';
    };

    subtest 'boolean: input' => sub {
        my $job = $t->app->minion->job( $run->{jobs}[6] );
        my $result = $job->info->{result};
        is $result->{output}, $input->{boolean}{value}, 'boolean input correct';
    };
    subtest 'boolean: output' => sub {
        is $context->{boolean_output}{value}, '1', 'boolean output correct';
    };

    subtest 'file: input' => sub {
        my $job = $t->app->minion->job( $run->{jobs}[8] );
        my $result = $job->info->{result};
        my $path = $t->app->home->child( 'uploads', $input->{file}{value} );
        is $result->{output}, $path->slurp, 'file input correct';
    };
    subtest 'file: output' => sub {
        my $path = $context->{file_output}{value};
        is $path, sprintf( 'run/%d/task/%d/zapp', $run->{run_id}, $run->{tasks}[9]{task_id} ),
            'file output correct';
        my $file = $t->app->home->child( 'uploads', $path );
        ok -e $file, 'path exists';
        is $file->slurp, "File output\n", 'file content is correct';
    };

    subtest 'enum: input' => sub {
        my $job = $t->app->minion->job( $run->{jobs}[10] );
        my $result = $job->info->{result};
        is $result->{output}, $input->{enum}{value}, 'enum input correct';
    };
    subtest 'enum: output' => sub {
        is $context->{enum_output}{value}, 'Katrina', 'enum output correct';
    };
};

done_testing;
