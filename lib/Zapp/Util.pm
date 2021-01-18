package Zapp::Util;

use Mojo::Base 'Exporter', -signatures;
our @EXPORT_OK = qw( get_path_from_data fill_input );

sub get_path_from_data( $path, $data ) {
    my $value = $data;
    for my $part ( $path =~ m{((?:\w+|\[\d+\]))(?=\.|\[|$)}g ) {
        if ( $part =~ /^\[(\d+)\]$/ ) {
            $value = $value->[ $1 ];
            next;
        }
        else {
            $value = $value->{ $part };
        }
    }
    return $value;
}

sub fill_input( $input, $data ) {
    if ( !ref $data ) {
        my $keys = join '|', keys %$input;
        return scalar $data =~ s{(?<!\\)\{\{($keys)\}\}}{$input->{$1}}reg
    }
    elsif ( ref $data eq 'ARRAY' ) {
        return [
            map { fill_input( $input, $_ ) }
            $data->@*
        ];
    }
    elsif ( ref $data eq 'HASH' ) {
        return {
            map { $_ => fill_input( $input, $data->{$_} ) }
            keys $data->%*
        };
    }
    die "Unknown ref type for data: " . ref $data;
}

1;
