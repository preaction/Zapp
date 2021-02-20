package Zapp::Type::File;
use Digest;
use Mojo::Base 'Zapp::Type', -signatures;
use Mojo::File;
use Mojo::Asset::File;

has path => sub( $self ) { $self->app->home->child( 'uploads' ) };

# "die" for validation errors

sub _digest_dir( $self, $asset ) {
    my $sha = Digest->new( 'SHA-1' );
    if ( $asset->is_file ) {
        ; say "File path: " . $asset->path;
        $sha->addfile( $asset->path );
    }
    else {
        $sha->add( $asset->slurp );
    }
    my $digest = $sha->b64digest =~ tr{+/}{-_}r;
    my @parts = split /(.{2})/, $digest, 3;
    my $dir = $self->path->child( @parts );
    $dir->make_path;
    return $dir;
}

sub _input( $self, $c, $upload ) {
    return undef if !defined $upload->filename || $upload->filename eq '';
    my $dir = $self->_digest_dir( $upload->asset );
    my $file = $dir->child( $upload->filename );
    ; $c->log->debug( "Saving file: $file" );
    $upload->move_to( $file );
    return $file->to_rel( $self->path );
}

# Form value -> Type value
sub plan_input( $self, $c, $form_value ) {
    return $self->_input( $c, $form_value );
}

# Form value -> Type value
sub run_input( $self, $c, $form_value ) {
    return $self->_input( $c, $form_value );
}

# For display on run view pages
sub display_value( $self, $c, $type_value ) {
    return $self->app->home->child( $type_value )->basename;
}

# Type value -> Task value
sub task_input( $self, $type_value ) {
    ; say "Task input (file): $type_value";
    return $self->path->child( $type_value )->to_abs;
}

# Task value -> Type value
sub task_output( $self, $task_value ) {
    ; say "Task output (file): $task_value";
    # Task gave us a path. Save the path and return the saved path.
    my $path = Mojo::File->new( $task_value );
    my $output_file = Mojo::Asset::File->new( path => "$path" );
    my $dir = $self->_digest_dir( $output_file );
    my $task_file = $dir->child( $path->basename );
    $output_file->move_to( $task_file );
    return $task_file->to_rel( $self->path );
}

1;
__DATA__
@@ input.html.ep
%= file_field 'value', value => $value, class => 'form-control'

@@ output.html.ep
%# Show a link to download the file
%= link_to $value => $value

