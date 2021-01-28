package Zapp::Task::Script;
use Mojo::Base 'Zapp::Task', -signatures;
use Mojo::File qw( tempdir tempfile );

sub schema( $class ) {
    return {
        input => {
            type => 'object',
            required => [qw( script )],
            properties => {
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
    my $dir = tempdir;
    my $file = tempfile( DIR => $dir, UNLINK => 1 );
    $file->spurt( $input->{script} );

    my ( $fh, $pid );
    if ( $input->{script} =~ /^\#!/ ) {
        $file->chmod( 0700 );
        $pid = open $fh, '-|', $file;
    }
    else {
        $pid = open $fh, '-|', $ENV{SHELL} // '/bin/sh', $file;
    }
    # XXX: Put PID somewhere we can use it

    if ( $pid <= 0 ) {
        return $self->fail({
            info => 'Could not execute script: ' . $!,
            output => '',
            exit => -1,
            pid => 0,
        });
    }

    my $output = '';
    while ( my $line = <$fh> ) {
        $output .= $line;
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
    return $self->$method({
        pid => $pid,
        output => $output,
        exit => $exit,
        info => $info,
    });
}

1;
__DATA__

@@ input.html.ep
% my $input = stash( 'input' ) // { script => '' };
<div class="form-group">
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
%= include 'zapp/task-bar', synopsis => begin
    <b><%= ( $task->{class} // '' ) =~ s/^Zapp::Task:://r %>: </b>
    <%= $task->{name} %>
% end
<div class="ml-4">
    <h3>Script</h3>
    <pre class="m-1 border p-1 rounded bg-light"><code><%= $task->{input}{script} %></code></pre>
    <h3>Output</h3>
    <pre class="m-1 border p-1 rounded bg-light"><output><%= $task->{output}{output} %></output></pre>
</div>

