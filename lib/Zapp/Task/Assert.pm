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
<ul class="assertions">
% for my $i ( 0 .. $#$args ) {
    % my $arg = $args->[ $i ];
    <li>
        <input type="text" name="[<%= $i %>].expr" value="<%= $arg->{expr} %>">
        <select name="[<%= $i %>].op">
            <option value="==" <%= $arg->{op} eq '==' ? 'selected' : '' %>>==</option>
            <option value="!=" <%= $arg->{op} eq '!=' ? 'selected' : '' %>>!=</option>
            <option value="&gt;" <%= $arg->{op} eq '>' ? 'selected' : '' %>>&gt;</option>
            <option value="&lt;" <%= $arg->{op} eq '<' ? 'selected' : '' %>>&lt;</option>
        </select>
        <input type="text" name="[<%= $i %>].value" value="<%= $arg->{value} %>">
        <button type="button" name="assert-remove">-</button>
    </li>
% }
</ul>
<button name="assert-add" type="button">+</button>

@@ args.js.ep
function addAssertion( event ) {
    // Clone the first row
    var button = event.target,
        list = button.previousElementSibling,
        row = list.querySelector('li'),
        newIndex = list.querySelectorAll('li').length,
        newRow = row.cloneNode(true);

    // Reset expr, op, value
    newRow.querySelectorAll( 'input,select' ).forEach( function (el) {
        if ( el.tagName == 'SELECT' ) {
            el.selectedIndex = 0;
        }
        else {
            el.value = '';
        }
        el.name = el.name.replace( /args\[\d+\]/, 'args[' + newIndex + ']' );
        el.id = el.name;
    } );

    // Append
    list.appendChild( newRow );
}

function removeAssertion( event ) {
    var button = event.target,
        row = button.parentElement,
        list = row.parentElement;

    // If the last row, clear it out
    if ( list.querySelectorAll( 'li' ).length == 1 ) {
        // Reset expr, op, value
        row.querySelectorAll( 'input,select' ).forEach( function (el) {
            if ( el.tagName == 'SELECT' ) {
                el.selectedIndex = 0;
            }
            else {
                el.value = '';
            }
        } );
    }
    // Else remove the row and re-index
    else {
        row.parentNode.removeChild( row );
        // Reset expr, op, value
        list.querySelectorAll( 'li' ).forEach( function (row, i) {
            row.querySelectorAll( 'input,select' ).forEach( function (el) {
                el.name = el.name.replace( /args\[\d+\]/, 'args[' + i + ']' );
                el.id = el.name;
            });
        } );
    }
}
document.addEventListener('DOMContentLoaded', function ( event ) {
    delegateEvent( 'click', 'button[name=assert-add]', addAssertion );
    delegateEvent( 'click', 'button[name=assert-remove]', removeAssertion );
});

@@ result.html.ep
%= dumper $result

