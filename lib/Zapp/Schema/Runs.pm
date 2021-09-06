package Zapp::Schema::Runs;
use Mojo::Base 'Zapp::Schema::Plans', -signatures;

has tasks_table  => 'run_tasks';
has inputs_table => 'run_inputs';

1;
