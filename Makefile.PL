# This file was automatically generated by Dist::Zilla::Plugin::MakeMaker v6.012.
use strict;
use warnings;

use 5.028;

use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
  "ABSTRACT" => "Write a sentence about what it does",
  "AUTHOR" => "Doug Bell <preaction\@cpan.org>",
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => 0
  },
  "DISTNAME" => "Zapp",
  "LICENSE" => "perl",
  "MIN_PERL_VERSION" => "5.028",
  "NAME" => "Zapp",
  "PREREQ_PM" => {
    "Minion" => "10.14",
    "Minion::Backend::SQLite" => "5.0.3",
    "Mojolicious" => "8.65",
    "Yancy" => "1.067"
  },
  "TEST_REQUIRES" => {
    "ExtUtils::MakeMaker" => 0,
    "File::Spec" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Minion::Backend::mysql" => "0.21",
    "Test::More" => 0,
    "Test::mysqld" => "1.0013"
  },
  "VERSION" => "0.001",
  "test" => {
    "TESTS" => "t/*.t t/controller/*.t t/task/*.t"
  }
);


my %FallbackPrereqs = (
  "ExtUtils::MakeMaker" => 0,
  "File::Spec" => 0,
  "IO::Handle" => 0,
  "IPC::Open3" => 0,
  "Minion" => "10.14",
  "Minion::Backend::SQLite" => "5.0.3",
  "Minion::Backend::mysql" => "0.21",
  "Mojolicious" => "8.65",
  "Test::More" => 0,
  "Test::mysqld" => "1.0013",
  "Yancy" => "1.067"
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);