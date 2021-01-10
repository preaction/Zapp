package Zapp::Util;

use Mojo::Base 'Exporter', -signatures;
our @EXPORT_OK = qw( get_path_from_data );

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

1;
