package Zapp::Model;
use Mojo::Base 'Yancy::Model', -signatures;
has minion => sub { die 'minion is required' };
1;
