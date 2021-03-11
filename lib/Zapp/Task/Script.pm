package Zapp::Task::Script;
use Mojo::Base 'Zapp::Task', -signatures;
use Mojo::File qw( tempdir tempfile );
use IPC::Open3 qw( open3 );
use Cwd qw( cwd );
use Symbol qw( gensym );

sub schema( $class ) {
    return {
        input => {
            type => 'object',
            required => [qw( script )],
            properties => {
                env => {
                    type => 'array',
                    items => {
                        type => 'object',
                        properties => {
                            name => {
                                type => 'string',
                            },
                            value => {
                                type => 'string',
                            },
                        },
                    },
                },
                script => {
                    type => 'string',
                    format => 'textarea',
                },
            },
        },
        output => {
            type => 'object',
            required => [qw( output )],
            properties => {
                output => {
                    type => 'string',
                    format => 'textarea',
                },
                pid => {
                    type => 'integer',
                },
                exit => {
                    type => 'integer',
                },
                info => {
                    type => 'string',
                },
            },
        },
    };
}

sub run( $self, $input ) {
    ; $self->app->log->debug( 'Running script: ' . $input->{script} );
    # The script came from the browser's form with \r\n as line ending
    # character, but we need to use the native OS's line ending
    # character...
    my $script = $input->{script} =~ s/\r\n/\n/gr;

    my $cwd = cwd;
    my $dir = tempdir;
    chdir $dir;
    my $file = tempfile( DIR => $dir, UNLINK => 1 );
    $file->spurt( $script );

    my ( $stdout, $stderr, $pid );
    $stderr = gensym;

    {
        local %ENV = %ENV;
        for my $var ( @{ $input->{vars} // [] } ) {
            $ENV{ $var->{name} } = $var->{value};
        }

        if ( $input->{script} =~ /^\#!/ ) {
            $file->chmod( 0700 );
            $pid = open3( my $stdin, $stdout, $stderr, $file );
        }
        else {
            $pid = open3( my $stdin, $stdout, $stderr, $ENV{SHELL} // '/bin/sh', $file );
        }
        # XXX: Put PID somewhere we can use it
    }

    if ( !$pid || $pid <= 0 ) {
        chdir $cwd;
        return $self->fail({
            info => 'Could not execute script: ' . $!,
            output => '',
            exit => -1,
            pid => 0,
            error_output => '',
        });
    }

    my $output = '';
    while ( my $line = <$stdout> ) {
        $output .= $line;
        # XXX: Put output somewhere it can be seen while process runs
    }
    my $error_output = '';
    while ( my $line = <$stderr> ) {
        $error_output .= $line;
        # XXX: Put output somewhere it can be seen while process runs
    }

    waitpid $pid, 0;
    my $exit = $?;
    my $info
        = $exit == -1 ? 'Could not execute script: ' . $!
        : $exit & 127 ? 'Script ended with signal: ' . ( $? & 127 )
        : 'Script exited with value: ' . ( $? >> 8 )
        ;
    $exit >>= 8;

    my $method = $exit == 0 ? 'finish' : 'fail';
    chdir $cwd;
    return $self->$method({
        pid => $pid,
        output => $output,
        exit => $exit,
        info => $info,
        error_output => $error_output,
    });
}

1;
__DATA__

@@ input.html.ep
<%
    my $input = stash( 'input' ) // { script => '' };
    my @vars = @{ $input->{vars} // [ {} ] };
%>
% my $row_tmpl = begin
    % my ( $i, $env ) = @_;
    <div data-zapp-array-row class="form-row">
        <div class="col">
            <label for="vars[<%= $i %>].name">Name</label>
            <input type="text" name="vars[<%= $i %>].name" value="<%= $env->{name} %>" class="form-control">
        </div>
        <div class="col">
            <label for="vars[<%= $i %>].value">Value</label>
            <input type="text" name="vars[<%= $i %>].value" value="<%= $env->{value} %>" class="form-control">
        </div>
        <div class="col-auto align-self-end">
            <button type="button" class="btn btn-outline-danger align-self-end" data-zapp-array-remove>
                <i class="fa fa-times-circle"></i>
            </button>
        </div>
    </div>
% end
<div class="form-group">
    <label for="vars">Environment Variables</label>
    <div data-zapp-array>
        <template><%= $row_tmpl->( '#', {} ) %></template>
        % for my $i ( 0 .. $#vars ) {
            %= $row_tmpl->( $i, $vars[$i] )
        % }
        <div class="form-row justify-content-end">
            <button type="button" class="btn btn-outline-success" data-zapp-array-add>
                <i class="fa fa-plus"></i>
            </button>
        </div>
    </div>

    <label for="script">Script</label>
    <div class="grow-wrap">
        <!-- XXX: support markdown -->
        <%= text_area "script", $input->{script},
            oninput => 'this.parentNode.dataset.replicatedValue = this.value',
            placeholder => 'Script',
        %>
    </div>
</div>

@@ output.html.ep
<h3>Script</h3>
% if ( my @vars = @{ $task->{input}{vars} // [] } ) {
    <h4>Environment Variables</h4>
    <dl>
        % for my $var ( @{ $task->{input}{vars} } ) {
            <dt><%= $var->{name} %></dt>
            <dd><%= $var->{value} %></dd>
        % }
    </dl>
% }
<pre data-input class="m-1 border p-1 rounded bg-light"><code><%= $task->{input}{script} %></code></pre>
% if ( $task->{output} && !ref $task->{output} ) {
    <h3>Error</h3>
    <div data-error class="alert alert-danger"><%= $task->{output} %></div>
% } elsif ( $task->{output} ) {
    <h3>Output</h3>
    % if ( $task->{output}{output} ) {
        <pre data-output class="m-1 border p-1 rounded bg-light"><output><%= $task->{output}{output} %></output></pre>
    % }
    % if ( $task->{output}{error_output} ) {
        <h4>Error Output</h4>
        <pre data-output class="m-1 border p-1 rounded table-warning"><output><%= $task->{output}{error_output} %></output></pre>
    % }
% }

