package Zapp::Task::Request;
use Mojo::Base 'Zapp::Task', -signatures;
use Mojo::JSON qw( false true );

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
                # XXX: Query params / Form params
                # XXX: Request headers
                # XXX: Cookies (must be easily passed between requests,
                # or automatically saved to the context)
                # XXX: JSON subclass that parses JSON responses
                # XXX: DOM subclass that extracts DOM text/attrs
            },
            additionalProperties => false,
        },
        result => {
            type => 'object',
            properties => {
                res => {
                    type => 'object',
                    properties => {
                        is_success => {
                            type => 'boolean',
                        },
                        code => {
                            type => 'integer',
                            minValue => 100,
                            maxValue => 599,
                        },
                        message => {
                            type => 'string',
                        },
                        body => {
                            type => 'string',
                        },
                        headers => {
                            type => 'object',
                            properties => {
                                content_type => {
                                    type => 'string',
                                },
                            },
                            additionalProperties => false,
                        },
                    },
                    additionalProperties => false,
                },
            },
            additionalProperties => false,
        },
    };
}

sub run( $self, $args ) {
    my $method = lc $args->{method};
    my $tx = $self->app->ua->$method( $args->{url} );
    $self->finish({
        res => {
            (
                map { $_ => $tx->res->$_ }
                qw( is_success code message body )
            ),
            headers => {
                map { $_ => $tx->res->headers->$_ }
                qw( content_type )
            },
        },
    });
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

