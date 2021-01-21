requires "Minion" => "10.14";
requires "Minion::Backend::SQLite" => "v5.0.3";
requires "Mojolicious" => "8.65";
requires "Yancy" => "1.067";
requires "perl" => "5.028";

on 'test' => sub {
  requires "ExtUtils::MakeMaker" => "0";
  requires "File::Spec" => "0";
  requires "IO::Handle" => "0";
  requires "IPC::Open3" => "0";
  requires "Minion::Backend::mysql" => "0.21";
  requires "Test::More" => "0";
  requires "Test::mysqld" => "1.0013";
};

on 'test' => sub {
  recommends "CPAN::Meta" => "2.120900";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};
