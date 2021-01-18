package Zapp::Task::Request;
use Mojo::Base 'Zapp::Task', -signatures;
use Mojo::JSON qw( false true );

sub schema( $class ) {
    return {
        input => {
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
                content_type => {
                    type => 'string',
                    enum => ['', qw( application/json )],
                    default => '',
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
        output => {
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

sub run( $self, $input ) {
    my $ua = $self->app->ua;
    $ua->max_redirects( 5 );
    #$self->app->log->debug( 'input: ' . $self->app->dumper( $input ) );
    my %headers;
    if ( $input->{auth} && $input->{auth}{type} eq 'bearer' ) {
        $headers{ Authorization } = join ' ', 'Bearer', $input->{auth}{token};
    }
    if ( $input->{content_type} ) {
        $headers{ 'Content-Type' } = $input->{content_type};
    }

    my $tx = $ua->build_tx(
        $input->{method} => $input->{url},
        \%headers,
        $input->{content_type} ? ( $input->{body} ) : (),
    );
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
                grep { $tx->res->headers->$_ }
                qw( content_type )
            },
            (
                $tx->res->headers->content_type =~ m{^application/json}
                ? (
                    json => $tx->res->json,
                )
                : ()
            ),
        },
    });
}

1;
__DATA__

@@ input.html.ep
<%
    my $input = stash( 'input' ) // { method => 'GET' };
    $input->{method} //= 'GET';
    $input->{auth} //= { type => '' };
%>

<div class="form-row">
    <div class="col-auto">
        <label for="method">Method</label>
        <%= select_field method =>
            [ map { $input->{method} eq $_ ? [ $_, $_, selected => 'selected' ] : $_ } qw( GET POST PUT DELETE PATCH ) ],
            class => 'form-control',
        %>
    </div>
    <div class="col">
        <label for="url">URL</label>
        %= text_field 'url', value => $input->{url}, class => 'form-control'
    </div>
</div>

<div class="form-row">
    <div class="col">
        <label for="content_type">Request Body Type</label>
        <%= select_field 'content_type' =>
            [
                [ 'None' => '' ],
                [ 'JSON' => 'application/json', $input->{content_type} eq 'application/json' ? ( selected => 'selected' ) : () ],
            ],
            class => 'form-control',
        %>
    </div>
</div>
<div data-zapp-if="content_type eq 'application/json'" class="form-row">
    <div class="col">
        <label for="body">JSON Body</label>
        <div class="grow-wrap">
            <%= text_area "body", $input->{body}, class => 'form-control',
                oninput => 'this.parentNode.dataset.replicatedValue = this.value',
            %>
        </div>
    </div>
</div>

<div class="form-row">
    <div class="col-auto">
        <label for="auth.type">Authentication</label>
        <%= select_field 'auth.type' =>
            [
                [ 'None' => '' ],
                [ 'Bearer Token' => 'bearer', $input->{auth}{type} eq 'bearer' ? ( selected => 'selected' ) : () ],
            ],
            class => 'form-control',
        %>
    </div>
    <div data-zapp-if="auth.type eq 'bearer'" class="col align-self-end">
        %= text_field 'auth.token', value => $input->{auth}{token}, class => 'form-control'
    </div>
</div>

@@ output.html.ep
%= include 'zapp/task-bar', synopsis => begin
    <b><%= ( $task->{class} // '' ) =~ s/^Zapp::Task:://r %>: </b>
    <%= $task->{input}{method} %>
    <%= $task->{input}{url} %>
% end
<%
    use Mojo::JSON qw( decode_json );
    my $body = $task->{output}{res}{body};
    if ( $task->{output}{res}{headers}{content_type} =~ m{^application/json} ) {
        $body = decode_json( $body );
    }
%>
<div class="ml-4">
    <h4>Request</h4>
    <pre class="bg-light border border-secondary p-1"><%= $task->{input}{method} %> <%= $task->{input}{url} %></pre>
    <h4>Response</h4>
    <dl>
        <dt>Code</dt>
        <dd><%= $task->{output}{res}{code} %> <%= $task->{output}{res}{message} %></dd>
        <dt>Content-Type</dt>
        <dd><%= $task->{output}{res}{headers}{content_type} // '' %></dd>
    </dl>
    <pre class="bg-light border border-secondary p-1"><%= dumper $body %></pre>
</div>

