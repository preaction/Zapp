package Zapp::Task::GetOAuth2Token;
use Mojo::Base 'Zapp::Task', -signatures;
use Mojo::JSON qw( false true );
use Mojo::Util qw( b64_encode );

sub schema( $class ) {
    return {
        args => {
            type => 'object',
            required => [qw( endpoint client_id client_secret )],
            properties => {
                endpoint => {
                    type => 'string',
                },
                client_id => {
                    type => 'string',
                },
                client_secret => {
                    type => 'string',
                },
                scope => {
                    type => 'string',
                },
            },
            additionalProperties => false,
        },
        result => {
            type => 'object',
            required => [qw( access_token token_type )],
            properties => {
                is_success => {
                    type => 'boolean',
                },
                # XXX: Add more validation here? Should invalid results
                # be accepted but flagged? Should users be able to fail
                # invalid results?
                access_token => {
                    type => 'string',
                },
                token_type => {
                    # We only understand Bearer tokens for now.
                    # https://tools.ietf.org/html/rfc6749#section-7.1
                    type => 'string',
                    enum => [qw( bearer )],
                },
                expires_in => {
                    type => 'integer',
                },
                refresh_token => {
                    type => 'string',
                },
                scope => {
                    type => 'string',
                },
            },
        },
    };
}

sub run( $self, $args ) {
    # An OAuth2 client credentials request is authenticated with HTTP
    # basic auth: The client_id is the username, the client_secret is
    # the password. https://tools.ietf.org/html/rfc6749#section-4.4
    my $url = Mojo::URL->new( $args->{endpoint} );
    my $auth = b64_encode( join( ':', $args->@{qw( client_id client_secret )} ), "" );
    my $tx = $self->app->ua->post(
        $url,
        {
            Authorization => 'Basic ' . $auth,
        },
        form => {
            grant_type => 'client_credentials',
            scope => $args->{ scope },
        },
    );

    # The response will be a JSON document. On success (200 OK) it will contain
    # the token. On failure (400 Bad Request) it will describe the
    # error.
    my $json = $tx->res->json;
    my %result = (
        is_success => $tx->res->is_success ? true : false,
    );
    # Success: https://tools.ietf.org/html/rfc6749#section-5.1
    if ( $result{is_success} ) {
        return $self->finish({
            %result,
            $json->%{qw( access_token token_type expires_in refresh_token )},
            # If scope is omitted, it is the same as the scope sent with the
            # request (https://tools.ietf.org/html/rfc6749#section-5.1)
            scope => $json->{scope} || $args->{scope},
        });
    }
    # Error: https://tools.ietf.org/html/rfc6749#section-5.2
    return $self->fail({
        %result,
        $json->%{qw( error error_description error_uri )},
    });
}

1;
__DATA__

@@ args.html.ep
% my $args = stash( 'args' ) // {};
<!-- XXX: A form this simple should be auto-generated from the schema -->
<div>
    <label for="endpoint">Endpoint</label>
    %= url_field 'endpoint', value => $args->{endpoint}
</div>
<div>
    <label for="client_id">Client ID</label>
    %= text_field 'client_id', value => $args->{client_id}
</div>
<div>
    <label for="client_secret">Client Secret</label>
    %= text_field 'client_secret', value => $args->{client_secret}
</div>
<div>
    <label for="scope">Scope</label>
    %= text_field 'scope', value => $args->{scope}
</div>

@@ result.html.ep
%= dumper $result

