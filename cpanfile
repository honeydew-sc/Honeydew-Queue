requires "Cwd" => "0";
requires "DBD::mysql" => "0";
requires "DBI" => "0";
requires "DDP" => "0";
requires "File::Spec" => "0";
requires "Getopt::Long" => "0";
requires "Honeydew::Config" => "0.05";
requires "Honeydew::ExternalServices::Crontab" => "0";
requires "Moo" => "0";
requires "Resque" => "0";
requires "Try::Tiny" => "0";
requires "feature" => "0";
requires "if" => "0";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "DBD::Mock" => "0";
  requires "File::Basename" => "0";
  requires "File::Temp" => "0";
  requires "Honeydew::Database" => "0";
  requires "Redis" => "0";
  requires "Sub::Install" => "0";
  requires "Test::More" => "0";
  requires "Test::RedisServer" => "0";
  requires "Test::Spec" => "0";
  requires "Test::mysqld" => "0";
  requires "lib" => "0";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};

on 'develop' => sub {
  requires "Pod::Coverage::TrustPod" => "0";
  requires "Test::Pod" => "1.41";
  requires "Test::Pod::Coverage" => "1.08";
};
