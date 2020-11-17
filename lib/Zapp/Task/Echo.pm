package Zapp::Task::Echo;
use Mojo::Base 'Zapp::Task', -signatures;

sub run( $self, @args ) {
    $self->finish({ args => \@args });
}

1;
__DATA__
@@ args.html.ep
This is for testing only (for now).
@@ result.html.ep
This is for testing only (for now). It may be used in the future to
write an arbitrary report to the output.
