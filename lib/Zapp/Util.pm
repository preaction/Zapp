package Zapp::Util;

use Mojo::Base 'Exporter', -signatures;
use Text::Balanced qw( extract_delimited );
our @EXPORT_OK = qw(
    build_data_from_params get_path_from_schema get_slot_from_data
    get_path_from_data prefix_field rename_field parse_zapp_attrs
    ansi_colorize
);

sub build_data_from_params( $c, $prefix='' ) {
    my $data = '';
    # XXX: Move to Yancy (Util? Controller?)
    my $dot = $prefix ? '.' : '';
    my @params = grep /^$prefix(?:\[\d+\]|\Q$dot\E\w+)/, $c->req->params->names->@*;
    for my $param ( @params ) {
        ; $c->log->debug( "Param: $param" );
        my $value = $c->param( $param );
        my $path = $param =~ s/^$prefix//r;
        my $slot = get_slot_from_data( $path, \$data );
        $$slot = $value;
    }
    my @uploads = grep $_->name =~ /^$prefix(?:\[\d+\]|\.\w+)/, $c->req->uploads->@*;
    for my $upload ( @uploads ) {
        ; $c->log->debug( "Upload: " . $upload->name );
        my $path = $upload->name =~ s/^$prefix//r;
        my $slot = get_slot_from_data( $path, \$data );
        $$slot = $upload;
    }
    ; $c->log->debug( "Build data: " . $c->dumper( $data ) );
    return $data ne '' ? $data : undef;
}

sub get_path_from_schema( $path, $schema ) {
    my $slot = $schema;
    for my $part ( $path =~ m{((?:\w+|\[\d*\]))(?=\.|\[|$)}g ) {
        if ( $part =~ /^\[\d*\]$/ ) {
            $slot = $slot->{ items };
            next;
        }
        else {
            $slot = $slot->{ properties }{ $part };
        }
    }
    return $slot;
}

sub get_slot_from_data( $path, $data ) {
    my $slot = $data;
    for my $part ( $path =~ m{((?:\w+|\[\d+\]))(?=\.|\[|$)}g ) {
        if ( $part =~ /^\[(\d+)\]$/ ) {
            my $part_i = $1;
            if ( !ref $$slot ) {
                $$slot = [];
            }
            $slot = \( $$slot->[ $part_i ] );
            next;
        }
        else {
            if ( !ref $$slot ) {
                $$slot = {};
            }
            $slot = \( $$slot->{ $part } );
        }
    }
    return $slot;
}

sub get_path_from_data( $path, $data ) {
    my $slot = get_slot_from_data( $path, \$data );
    return $$slot;
}

sub prefix_field( $dom, $prefix ) {
    if ( ref $dom ne 'Mojo::DOM' ) {
        $dom = Mojo::DOM->new( $dom );
    }

    $dom->find( 'input,select,textarea' )->each(
        sub {
            my ( $el ) = @_;
            my $name = $el->attr( 'name' );
            my $joiner = $name =~ /^\[/ ? '' : '.';
            $el->attr( name => join $joiner, $prefix, $name );
            $el->attr( id => $el->attr( 'name' ) );
        },
    );
    $dom->find( 'label' )->each(
        sub {
            my ( $el ) = @_;
            my $for = $el->attr( 'for' );
            my $joiner = $for =~ /^\[/ ? '' : '.';
            $el->attr( for => join $joiner, $prefix, $for );
        },
    );

    return $dom;
}

sub rename_field( $dom, %map ) {
    if ( ref $dom ne 'Mojo::DOM' ) {
        $dom = Mojo::DOM->new( $dom );
    }

    $dom->find( 'input,select,textarea' )->each(
        sub {
            my ( $el ) = @_;
            my $name = $el->attr( 'name' );
            $el->attr( name => $name =~ s{$name}{$map{ $name } // $name}er );
            $el->attr( id => $el->attr( 'name' ) );
        },
    );
    $dom->find( 'label' )->each(
        sub {
            my ( $el ) = @_;
            my $for = $el->attr( 'for' );
            $el->attr( for => $for =~ s{$for}{$map{ $for } // $for}re );
        },
    );

    return $dom;
}

sub parse_zapp_attrs( $dom, $data ) {
    if ( ref $dom ne 'Mojo::DOM' ) {
        $dom = Mojo::DOM->new( $dom );
    }

    $dom->find( '[data-zapp-if]' )->each(
        sub {
            my ( $el ) = @_;
            my ( $lhs, $op, $rhs ) = split /\s*(==|!=|>|<|>=|<=|eq|ne|gt|lt|ge|le)\s*/, $el->attr( 'data-zapp-if' ), 3;
            #; say "Expr: " . $el->attr( 'data-zapp-if' );
            #; say "LHS: $lhs; OP: $op; RHS: $rhs";
            if ( !$op ) {
                # Boolean LHS
                my ( $false, $path ) = $lhs =~ /^(!)?\s*(\S+)/;
                my $value = get_path_from_data( $path, $data );
                if ( ( !$false && $value ) || ( $false && !$value ) ) {
                    #; say "False: $false; Value: $value";
                    $el->attr( class => join ' ', $el->attr( 'class' ), 'zapp-visible' );
                }
            }
            else {
                my ( $lhs_value, $rhs_value );
                if ( $lhs_value = extract_delimited( $lhs ) ) {
                    $lhs_value =~ s/^['"`]|['"`]$//g;
                }
                else {
                    $lhs_value = get_path_from_data( $lhs, $data );
                }
                if ( $rhs_value = extract_delimited( $rhs ) ) {
                    $rhs_value =~ s/^['"`]|['"`]$//g;
                }
                else {
                    $rhs_value = get_path_from_data( $rhs, $data );
                }

                my %ops = (
                    map { $_ => eval "sub { shift() $_ shift() }" } qw( == != > < >= <= eq ne gt lt ge le ),
                );
                #; say "LHS: $lhs_value ($lhs); OP: $op; RHS: $rhs_value ($rhs)";
                if ( $ops{ $op } && $ops{ $op }->( $lhs_value, $rhs_value ) ) {
                    $el->attr( class => join ' ', $el->attr( 'class' )//(), 'zapp-visible' );
                }
            }
        },
    );

    return $dom;
}

# 256 colors
# 0x00-0x07:  standard colors (same as the 4-bit colours)
# 0x08-0x0F:  high intensity colors
# 0x10-0xE7:  6 × 6 × 6 cube (216 colors): 16 + 36 × r + 6 × g + b (0 ≤ r, g, b ≤ 5)
# 0xE8-0xFF:  grayscale from black to white in 24 steps

my %colors;
$colors{8} = {
    # Foreground     # Background
    30 => 'black',   40 => 'black',
    31 => 'maroon',  41 => 'maroon',
    32 => 'green',   42 => 'green',
    33 => 'olive',   43 => 'olive',
    34 => 'navy',    44 => 'navy',
    35 => 'purple',  45 => 'purple',
    36 => 'teal',    46 => 'teal',
    37 => 'silver',  47 => 'silver',
    90 => 'gray',    100 => 'gray',
    91 => 'red',     101 => 'red',
    92 => 'lime',    102 => 'lime',
    93 => 'yellow',  103 => 'yellow',
    94 => 'blue',    104 => 'blue',
    95 => 'fuchsia', 105 => 'fuchsia',
    96 => 'aqua',    106 => 'aqua',
    97 => 'white',   107 => 'white',
};

$colors{256} = {
    # First 15 colors are mapped from above
    ( map { $_ - 30 => $colors{8}{$_} } 30..37 ),
    ( map { $_ - 82 => $colors{8}{$_} } 90..97 ),
    # Next 216 are cubes calculated thusly
    (
        map { my $r = $_;
            map { my $g = $_;
                map { my $b = $_;
                    16 + 36*$r + 6*$g + $b => sprintf 'rgb(%d,%d,%d)', $r*36, $g*36, $b*36,
                } 0..5
            } 0..5
        } 0..5
    ),

    # Final 24 are shades of gray
    ( map { 232 + $_ => sprintf 'rgb(%d,%d,%d)', (8 + $_*10)x3 } 0..23 ),
};


sub ansi_colorize( $text ) {
    my @parts = split /\e\[([\d;]*)m/, $text;
    ; use Data::Dumper;
    ; say Dumper \@parts;
    return $parts[0] if @parts == 1;
    my $output = shift @parts;
    my %context;
    while ( my $code = shift @parts ) {
        my @styles = split /;/, $code;
        if ( !@styles ) {
            @styles = ( 0 );
        }
        while ( my $style = shift @styles ) {
            # 0 reset
            if ( $style == 0 ) {
                %context = ();
            }
            # 1 bold
            elsif ( $style == 1 ) {
                $context{ bold } = 'font-weight: bold';
            }
            # 22 unbold
            elsif ( $style == 22 ) {
                delete $context{ bold };
            }
            # 4 underline
            elsif ( $style == 4 ) {
                $context{ underline } = 'text-decoration: underline';
            }
            # 24 not underlined
            elsif ( $style == 24 ) {
                delete $context{ underline };
            }
            # 30-37,90-97 foreground color
            elsif ( ( $style >= 30 && $style <= 37 ) || ( $style >= 90 && $style <= 97 ) ) {
                $context{ color } = 'color: ' . $colors{8}{ $style };
            }
            elsif ( $style == 38 ) {
                my $type = shift @styles;
                # 38;5 256-color
                if ( $type == 5 ) {
                    $context{ color } = 'color: ' . $colors{256}{ shift @styles };
                }
                # 38;2 RGB color (0-255)
                elsif ( $type == 2 ) {
                    my ( $r, $g, $b ) = splice @styles, 0, 3;
                    $context{ color } = sprintf 'color: rgb(%d,%d,%d)', $r, $g, $b;
                }
            }
            # 39 reset foreground
            elsif ( $style == 39 ) {
                delete $context{ color };
            }
            # 40-47,100-107 background color
            elsif ( ( $style >= 40 && $style <= 47 ) || ( $style >= 100 && $style <= 107 ) ) {
                $context{ background } = 'background: ' . $colors{8}{ $style };
            }
            elsif ( $style == 48 ) {
                my $type = shift @styles;
                # 48;5 256-color
                if ( $type == 5 ) {
                    $context{ background } = 'background: ' . $colors{256}{ shift @styles };
                }
                # 48;2 RGB color (0-255)
                elsif ( $type == 2 ) {
                    my ( $r, $g, $b ) = splice @styles, 0, 3;
                    $context{ background } = sprintf 'background: rgb(%d,%d,%d)', $r, $g, $b;
                }
            }
            # 49 reset background
            elsif ( $style == 49 ) {
                delete $context{ background };
            }
        }

        $output .= sprintf( '<span style="%s">', join '; ', sort values %context )
            . shift( @parts ) 
            . '</span>';
    }

    return $output;
}

1;
