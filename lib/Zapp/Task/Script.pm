package Zapp::Task::Script;
use Mojo::Base 'Zapp::Task', -signatures;

sub schema( $class ) {
    return {
        args => {
            type => 'object',
            required => [qw( script )],
            properties => {
                script => {
                    type => 'string',
                    format => 'textarea',
                },
            },
        },
    };
}

1;
__DATA__

@@ args.html.ep
% my $args = stash( 'args' ) // { script => '' };
<div>
    <label for="script">Script</label>
    <%= text_area 'script', begin %><%= $args->{script} %><% end %>
</div>

@@ output.html.ep
%= dumper $output

