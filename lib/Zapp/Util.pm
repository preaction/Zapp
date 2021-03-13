package Zapp::Util;

use Mojo::Base 'Exporter', -signatures;
use Text::Balanced qw( extract_delimited );
our @EXPORT_OK = qw(
    build_data_from_params get_path_from_schema get_slot_from_data
    get_path_from_data prefix_field rename_field parse_zapp_attrs
);

sub build_data_from_params( $c, $prefix ) {
    my $data = '';
    # XXX: Move to Yancy (Util? Controller?)
    my @params = grep /^$prefix(?:\[\d+\]|\.\w+)/, $c->req->params->names->@*;
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

1;
