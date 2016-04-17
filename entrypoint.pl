#!/usr/bin/env perl

use strict;
use warnings;

$| = 1;

# Prevent the script from being ran by accident:
die "This script can only be run via the rapi/proxy-hub docker image.\n"
  unless($ENV{RAPI_PROXY_HUB_DOCKERIZED}); # Set in the rapi/proxy-hub Dockerfile

my @exit_sigs = qw/INT KILL TERM QUIT/;  
for my $sig (@exit_sigs) {
  $SIG{$sig} = sub { exit };
}

my @ssh_cmd = &_get_ssh_cmd(@ARGV);


qx|/setup_ssh.sh 1>&2|;

fork || &_loop_fork_exec(qw|/usr/sbin/sshd -D -d|);
fork || &_loop_fork_exec(@ssh_cmd);

sleep 1;
print "\n\n --> " . join(' ',@ssh_cmd) . "\n\n";

sleep 1 while(1);


##############################################################################
##############################################################################

sub _loop_fork_exec {
  while(1) {
    if(my $pid = fork) {
      waitpid($pid,0);
    }
    else {
      exec @_
    }
  }
}


sub _get_ssh_cmd {
  my @args = @_;
  my $eg = "'<BIND_PORT>:<HOSTNAME>:<PORT>'";
  
  die "No port/proxy ($eg) arguments supplied\n" unless (scalar(@args) > 0);
  
  my @cmd = ('ssh');
  
  for my $arg (@args) {
    my ($local_port,$host,$remote_port) = split(/\:/,$arg);
    die "'$arg' is not a valid port/proxy ($eg) argument\n" unless (
      &_valid_port($local_port) &&
      $host && $host =~ /^[0-9a-z\-\.]+$/i &&
      &_valid_port($remote_port)
    );
    
    push @cmd, '-R', join(':','*',$local_port,$host,$remote_port);
  }
  
  return @cmd, '127.0.0.1','-N'
}


 sub _valid_port {
  my $port = shift;
  return (
    $port && $port =~ /^\d+$/ &&
    $port > 0 && $port < 2**16
  )
}