package Zapp::Task;
use Mojo::Base 'Minion::Job', -signatures;

sub schema( $class ) {
    return {
        args => {
            type => 'array',
        },
        result => {
            type => 'string',
        },
    };
}

1;
