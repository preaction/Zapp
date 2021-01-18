package Zapp::Task::Echo;
use Mojo::Base 'Zapp::Task', -signatures;

sub run( $self, @args ) {
    $self->finish(@args);
}

1;
__DATA__
@@ args.html.ep
This is for testing only (for now).
@@ output.html.ep
%= include 'zapp/task-bar', synopsis => begin
    <b><%= ( $task->{class} // '' ) =~ s/^Zapp::Task:://r %>: </b>
% end
<div class="ml-4">
    <h4>Echo</h4>
    <pre class="bg-light border border-secondary p-1"><%= dumper $task->{args} %></pre>
</div>
