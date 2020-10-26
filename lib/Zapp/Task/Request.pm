package Zapp::Task::Request;
use Mojo::Base 'Zapp::Task', -signatures;

sub schema( $class ) {
    return {
        args => {
            type => 'object',
            required => [qw( url )],
            properties => {
                url => {
                    type => 'string',
                },
                method => {
                    type => 'string',
                    enum => [qw( GET POST PUT DELETE PATCH OPTIONS PROPFIND )],
                    default => 'GET',
                },
            },
        },
        result => {
            'x-template' => 'zapp/task/request/result',
            type => 'object',
            properties => {
                head => {
                    type => 'object',
                    properties => {
                    },
                    additionalProperties => {
                        type => 'string',
                    },
                },
                dom => {
                    type => 'string',
                    format => 'html',
                },
                json => {
                    type => 'string',
                    format => 'json',
                },
            },
        },
    };
}

1;
__DATA__

@@ args.html.ep
% my $args = stash( 'args' ) // { method => 'GET' };
<div>
    <label for="url">URL</label>
    %= url_field 'url', value => $args->{url}
</div>
<div>
    <label for="method">Method</label>
    %= select_field method => [ map { $args->{method} eq $_ ? [ $_, $_, selected => 'selected' ] : $_ } qw( GET POST PUT DELETE PATCH ) ]
</div>

@@ result.html.ep
%= dumper $result

