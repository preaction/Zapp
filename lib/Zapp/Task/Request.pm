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
                auth => {
                    type => 'object',
                    properties => {
                        type => {
                            type => 'string',
                            enum => [ '', qw( bearer )],
                        },
                        token => {
                            type => 'string',
                        },
                    },
                    additionalProperties => false,
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
    my $ua = $self->app->ua;
    my %headers;
    if ( $args->{auth} && $args->{auth}{type} eq 'bearer' ) {
        $headers{ Authorization } = join ' ', 'Bearer', $args->{auth}{token};
    }
    my $tx = $ua->build_tx( $args->{method}, $args->{url}, \%headers );
    $ua->start( $tx );
    my $method = $tx->res->is_success ? 'finish' : 'fail';
    $self->$method({
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
<%
    my $args = stash( 'args' ) // { method => 'GET' };
    $args->{method} //= 'GET';
    $args->{auth} //= { type => '' };
%>

<div>
    <label for="url">URL</label>
    %= url_field 'url', value => $args->{url}
</div>
<div>
    <label for="method">Method</label>
    %= select_field method => [ map { $args->{method} eq $_ ? [ $_, $_, selected => 'selected' ] : $_ } qw( GET POST PUT DELETE PATCH ) ]
</div>
<div>
    <label for="auth.type">Auth Type</label>
    %= select_field 'auth.type' => [ [ 'None' => '' ], [ 'Bearer Token' => 'bearer', $args->{auth}{type} eq 'bearer' ? ( selected => 'selected' ) : () ] ]
    <div data-zapp-if="auth.type eq 'bearer'">
        <label for="auth.token">Bearer Token</label>
        %= text_field 'auth.token', value => $args->{auth}{token}
    </div>
</div>

@@ result.html.ep
%= dumper $result

