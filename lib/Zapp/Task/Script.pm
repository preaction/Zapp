package Zapp::Task::Script;
use Mojo::Base 'Zapp::Task', -signatures;

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
    };
}

1;
__DATA__

@@ input.html.ep
% my $input = stash( 'input' ) // { script => '' };
<div>
    <label for="script">Script</label>
    <%= text_area 'script', begin %><%= $input->{script} %><% end %>
</div>

@@ output.html.ep
%= dumper $output

