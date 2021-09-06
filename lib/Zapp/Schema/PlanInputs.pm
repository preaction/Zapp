package Zapp::Schema::PlanInputs;
use Mojo::Base 'Yancy::Model::Schema', -signatures;
use Mojo::JSON qw( encode_json decode_json );

sub name { 'zapp_plan_inputs' }

sub create( $self, $input ) {
    $input->{value} &&= encode_json( $input->{value} );
    return $self->SUPER::create( $input );
}

sub build_item( $self, $item ) {
    $item->{value} &&= decode_json( $item->{value} );
    $item->{config} &&= decode_json( $item->{config} );
    return $self->SUPER::build_item( $item );
}

1;
