package Zapp::Task;

=head1 SYNOPSIS

    package My::Task::Greet;
    use Mojo::Base 'Zapp::Task', -signatures;

    # Perform the task
    sub run( $self, $input ) {
        return $self->fail( 'No-one to greet' ) if !$input->{who};
        return $self->finish({
            greeting => "Hello, $input->{who}!",
        });
    }

    __DATA__
    @@ input.html.ep
    %# Display the form to configure this task
    %= text_field 'who', value => $input->{who}

    @@ output.html.ep
    %# Show the result of this task
    %# XXX: Switch to $task->{error} if it's an actual error
    % if ( !ref $task->{output} ) {
        <p>I couldn't send a greeting: <%= $task->{output} %></p>
    % }
    % else {
        <p>I sent a greeting of <q><%= $task->{output}{greeting} %></q></p>
    % }

=head1 DESCRIPTION

=head1 SEE ALSO

L<Zapp::Task::Action>, L<Zapp>

=cut

use Mojo::Base 'Minion::Job', -signatures;
use List::Util qw( uniq );
use Time::Piece;
use Mojo::JSON qw( decode_json encode_json );
use Zapp::Util qw( get_path_from_data get_path_from_schema );

has zapp_task => sub( $self ) {
    my ( $task ) = $self->app->yancy->list( zapp_run_tasks => { job_id => $self->id } );
    return $task;
};

has zapp_run => sub( $self ) {
    my $task = $self->zapp_task;
    return $self->app->yancy->get( zapp_runs => $task->{run_id} );
};

# Cached lookups of output from run input and output from other tasks in
# this run. Run input is added here. Task output is filled-in by context()
# XXX: Make a Zapp::Run class to put this code, accessible from
# $self->app->zapp->run()
has _context => sub( $self ) {
    my $run_input = decode_json( $self->zapp_run->{ input } );
    my %context;
    for my $name ( keys %$run_input ) {
        my $input = $run_input->{ $name };
        my $type = $self->app->zapp->types->{ $input->{type} }
            or die qq{Could not find type "$input->{type}"};
        $context{ $name } = $type->task_input( $input->{config}, $input->{value} );
    }
    return \%context;
};

sub new( $class, @args ) {
    my $self = $class->SUPER::new( @args );
    # Process the initial arguments passed-in
    $self->args( $self->args );
    return $self;
}

sub set( $self, %values ) {
    ; say sprintf 'Setting task %s: %s', $self->id, $self->app->dumper( \%values );
    $self->app->yancy->backend->set(
        zapp_run_tasks => $self->zapp_task->{task_id},
        \%values,
    );
    if ( exists $values{state} ) {
        my $run = $self->zapp_run;
        my $run_state = $run->{state};
        if ( $values{state} =~ /(active|failed|stopped|killed)/ && $run->{state} ne $values{state} ) {
            # One job in these states can change the run state
            $run_state = $values{state};
        }
        elsif ( $values{state} =~ /(inactive|finished)/ ) {
            # All tasks must be in this state to change the run state
            my @task_states = uniq map $_->{state}, $self->app->yancy->list( zapp_run_tasks => { $run->%{'run_id'} } );
            if ( @task_states == 1 && $task_states[0] eq $values{state} ) {
                $run_state = $values{state};
            }
        }

        if ( $run_state ne $run->{state} ) {
            $self->app->yancy->backend->set(
                zapp_runs => $run->{run_id},
                {
                    state => $run_state,
                    (
                        $run_state eq 'active' ? ( started => Time::Piece->new( $self->info->{started} )->datetime )
                        : $run_state ne 'inactive' ? ( finished => Time::Piece->new( $self->info->{finished} )->datetime )
                        : ()
                    ),
                },
            );
        }
    }
}

sub context( $self, $var ) {
    my $context = $self->_context;
    my ( $name ) = $var =~ m{^([^\[.]+)};
    if ( !$context->{ $name } ) {
        my ( $task ) = $self->app->yancy->list(
            zapp_run_tasks => {
                $self->zapp_run->%{'run_id'},
                name => $name,
            },
        );
        if ( $task && $task->{state} eq 'finished' ) {
            $context->{ $name } = decode_json( $task->{output} );
        }
    }
    return get_path_from_data( $var, $context );
}

sub args( $self, $new_args=undef ) {
    if ( $new_args ) {
        # Process before storing
        my $args = $self->process_input( $new_args );
        return $self->SUPER::args( $args );
    }
    return $self->SUPER::args;
}

sub execute( $self, @args ) {
    $self->set( state => 'active' );
    return $self->SUPER::execute( @args );
}

sub finish( $self, $output=undef ) {
    return $self->SUPER::finish if !defined $output; # XXX: Minion calls this again after we do inside the task?
    my $run_job = $self->zapp_task;
    my ( $run_id, $task_id ) = $run_job->@{qw( run_id task_id )};

    # XXX: Run output through task_output

    ; $self->app->log->debug( 'Output: ' . $self->app->dumper( $output ) );
    $self->app->yancy->backend->set(
        zapp_run_tasks => $task_id,
        { output => encode_json( $output ) },
    );

    my $ok = $self->SUPER::finish( $output );
    # Set state after so run `finished` timestamp can be set
    $self->set( state => 'finished' );
    return $ok;
}

sub fail( $self, @args ) {
    $self->set( state => 'failed' );
    return $self->SUPER::fail( @args );
}

our %BINOPS = (
    '+' => sub { $_[0] + $_[1] },
    '-' => sub { $_[0] - $_[1] },
    '*' => sub { $_[0] * $_[1] },
    '/' => sub { $_[0] / $_[1] },
    '^' => sub { $_[0] ** $_[1] },
    '&' => sub { $_[0] . $_[1] },
    # XXX: Logical binops need to detect numbers vs. strings and change
    # comparisons
    '=' => sub { $_[0] eq $_[1] },
    '>' => sub { $_[0] gt $_[1] },
    '<' => sub { $_[0] lt $_[1] },
    '>=' => sub { $_[0] ge $_[1] },
    '<=' => sub { $_[0] le $_[1] },
    '<>' => sub { $_[0] ne $_[1] },
);

our %FUNCTIONS = (
    ### Text functions
    # Case manipulation
    LOWER => sub( $str ) { lc $str },
    UPPER => sub( $str ) { uc $str },
    PROPER => sub( $str ) { ( lc $str ) =~ s/(?:^|[^a-zA-Z'])([a-z])/uc $1/er },
    # Substrings
    LEFT => sub( $str, $len ) { substr $str, 0, $len },
    RIGHT => sub( $str, $len ) { substr $str, -$len },
);

my ( @term, @args, @binop, @call, $depth, $expected, $failed_at );
our $GRAMMAR = qr{
    (?(DEFINE)
        (?<EXPR>
            # Expressions can recurse, so we need to use a stack. When
            # we recurse, we must take the result off the stack and save
            # it until we can put it back on the stack (somewhere)
            (?{ $depth++ })(?>
            (?:
                # Terminator first, to escape infinite loops
                (?> (?&TERM) ) (?! (?&OP) | \( )
                (?{ push @Zapp::Task::result, pop @term })
                (?{ $expected = 'Expected operator'; $failed_at = pos() })
            |
                (?> (?&CALL) ) (?! (?&OP) )
                (?{ push @Zapp::Task::result, [ call => @{ pop @call } ] })
                (?{ $expected = 'Expected operator'; $failed_at = pos() })
            |
                (?{ push @binop, [] })
                (?>
                    (?> (?&CALL) )
                    (?{ push @{ $binop[-1] }, [ call => @{ pop @call } ] })
                |
                    (?> (?&TERM) )
                    (?{ push @{ $binop[-1] }, [ @{ pop @term } ] })
                )
                (?<op> (?&OP) )
                (?{ $expected = 'Expected variable, number, string, or function call'; $failed_at = pos() })
                (?>
                    (?> (?&CALL) )
                    (?{ push @{ $binop[-1] }, [ call => @{ pop @call } ] })
                |
                    (?> (?&TERM) )
                    (?{ push @{ $binop[-1] }, [ @{ pop @term } ] })
                )
                (?{ push @Zapp::Task::result, [ binop => $+{op}, @{ pop @binop } ] })
            )
            )(?{ $depth-- })
        )
        (?<OP>(?> @{[ join '|', map quotemeta, keys %BINOPS ]} ))
        (?<CALL>(?>
            (?<name> (?&VAR) )
            \(
                (?>
                    (?{ push @args, [] })
                    (?> (?&EXPR) )
                    (?{ push @{ $args[-1] }, pop @Zapp::Task::result })
                    (?:
                        , (?> (?&EXPR) )
                        (?{ push @{ $args[-1] }, pop @Zapp::Task::result })
                    )*
                )
                (?{ $expected = 'Could not find end parenthesis'; $failed_at = pos() })
            \)
            (?{ push @call, [ $+{name}, @{ pop @args } ] })
        ))
        (?<TERM>(?>
            (?:
                (?<string> (?&STRING) )
                (?{ push @term, [ %+{'string'} ] })
            |
                (?<number> (?&NUMBER) )
                (?{ push @term, [ %+{'number'} ] })
            |
                (?<var> (?&VAR) )
                (?{ push @term, [ %+{'var'} ] })
            )
        ))
        (?<VAR> [a-zA-Z][a-zA-Z0-9_.]* )
        (?<STRING>
            "
            (?>
                [^"\\]*+  (?: \\" [^"\\]*+ )*+
            )
            (?{ $expected = 'Could not find closing quote for string'; $failed_at = pos() })
            "
        )
        (?<NUMBER> -? \d+ %? | -? \d* \. \d+ %? )
    )
}xms;

# XXX: Strings that look like money amounts can be coerced into numbers
# XXX: Strings that look like dates can be coerced into dates
#       ... Or maybe not, since that's one of the biggest complaints
#       about Excel. Though, that might just refer to the
#       auto-formatting thing, which we will not be doing.

# Does not expect `=` prefix
sub parse_expr( $expr ) {
    local @Zapp::Task::result = ();
    $depth = 0;
    $expected = '';
    $failed_at = 0;
    unless ( $expr =~ /${GRAMMAR}^(?&EXPR)$/ ) {
        # XXX: Parse error handling. DCONWAY has numerous
        # (?{ $expected = '...'; $failed_at = pos() }) in his
        # Keyword::Declare grammar. If parsing stops, the last value in
        # those vars is used to show an error message.
        $failed_at = 'end of input' if $failed_at >= length $expr;
        die "Syntax error: $expected at $failed_at.\n";
    }
    return $Zapp::Task::result[0];
}

# Does not expect `=` prefix
sub eval_expr( $self, $expr ) {
    my $tree = parse_expr( $expr );
    my $handle = sub( $tree ) {
        if ( $tree->[0] eq 'string' ) {
            # XXX: strip slashes
            my $string = substr $tree->[1], 1, -1;
            $string =~ s/\\(?!\\)//g;
            return $string;
        }
        if ( $tree->[0] eq 'number' ) {
            return $tree->[1];
        }
        if ( $tree->[0] eq 'var' ) {
            return $self->context( $tree->[1] );
        }
        if ( $tree->[0] eq 'call' ) {
            my $name = $tree->[1];
            my @args = map { __SUB__->( $_ ) } @{$tree}[2 .. $#{$tree}];
            return $FUNCTIONS{ $name }->( @args );
        }
        if ( $tree->[0] eq 'binop' ) {
            my $op = $tree->[1];
            my $left = __SUB__->( $tree->[2] );
            my $right = __SUB__->( $tree->[3] );
            return $BINOPS{ $op }->( $left, $right );
        }
        die "Unknown parse result: $tree->[0]";
    };
    my $result = $handle->( $tree );
    return $result;
}

# XXX: Process input and output are the same subroutines with two small
# changes: 1. task_(input|output) 2. input calls eval_expr

sub process_input( $self, $input ) {
    if ( !ref $input ) {
        if ( $input =~ /^=(?!=)/ ) {
            $input = $self->eval_expr( substr $input, 1 );
        }
        # XXX: Run through task_input
        return $input;
    }
    elsif ( ref $input eq 'ARRAY' ) {
        return [
            map { $self->process_input( $_ ) }
            $input->@*
        ];
    }
    elsif ( ref $input eq 'HASH' ) {
        return {
            map { $_ => $self->process_input( $input->{$_} ) }
            keys $input->%*
        };
    }
    die "Unknown ref type for data: " . ref $input;
}

sub process_output( $self, $output, $path='' ) {
    if ( !ref $output ) {
        # XXX: Find type in schema and run through task_output
        my $schema = get_path_from_schema( $path, $self->schema->{output} );
        return $output;
    }
    elsif ( ref $output eq 'ARRAY' ) {
        return [
            map { $self->process_output( $output->[ $_ ], $path . "[$_]" ) }
            0..$output->$#*
        ];
    }
    elsif ( ref $output eq 'HASH' ) {
        return {
            map { $_ => $self->process_output( $output->{$_}, $path . ".$_" ) }
            keys $output->%*
        };
    }
    die "Unknown ref type for data: " . ref $output;
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
