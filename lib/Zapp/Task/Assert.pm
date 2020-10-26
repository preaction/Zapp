package Zapp::Task::Assert;
use Mojo::Base 'Zapp::Task', -signatures;

sub schema( $class ) {
    return {
        args => {
            type => 'array',
            items => {
                type => 'object',
                properties => {

                },
            },
        },
        result => {
            type => 'object',
            properties => {
                ok => {
                    type => 'boolean',
                },
                pass => {
                    type => 'integer',
                    description => 'Number of passed assertions',
                },
                fail => {
                    type => 'integer',
                    description => 'Number of failed assertions',
                    minValue => 0,
                },
            },
        },
    }
}

1;
__DATA__

@@ args.html.ep
% my $args = stash( 'args' ) // [ { op => '==' } ];
% for my $i ( 0 .. $#$args ) {
    % my $arg = $args->[ $i ];
    <div>
        <input type="text" name="[<%= $i %>].expr" value="<%= $arg->{expr} %>">
        <select name="[<%= $i %>].op">
            <option <%= $arg->{op} eq '==' ? 'selected' : '' %>>==</option>
            <option <%= $arg->{op} eq '!=' ? 'selected' : '' %>>!=</option>
            <option <%= $arg->{op} eq '>' ? 'selected' : '' %>>&gt;</option>
            <option <%= $arg->{op} eq '<' ? 'selected' : '' %>>&lt;</option>
        </select>
        <input type="text" name="[<%= $i %>].value" value="<%= $arg->{value} %>">
        <button type="button" name="assert-remove">-</button>
    </div>
% }
<button name="assert-add" type="button">+</button>

%= content_for 'after_form' => begin
    %= javascript begin
        function addAssertion( event ) {
            // Clone the first row
            // Reset expr, op, value
            // Append
        }
        function removeAssertion( event ) {
            // Remove the row
        }
        document.addEventListener('DOMContentLoaded', function ( event ) {
            delegateEvent( 'click', 'button[name=assert-add]', addAssertion );
            delegateEvent( 'click', 'button[name=assert-remove]', removeAssertion );
        });
    % end
% end

@@ result.html.ep
%= dumper $result

