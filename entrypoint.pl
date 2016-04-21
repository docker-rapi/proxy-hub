#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw/getcwd abs_path/;

$| = 1;

# Prevent the script from being ran by accident:
die "This script can only be run via the rapi/proxy-hub docker image.\n"
  unless($ENV{RAPI_PROXY_HUB_DOCKERIZED}); # Set in the rapi/proxy-hub Dockerfile

my @exit_sigs = qw/INT KILL TERM QUIT/;  
for my $sig (@exit_sigs) {
  $SIG{$sig} = sub { exit };
}

my $client_ids;
my $client_id_dir = '/opt/ids';

my $cmd_dir = '/var/run/proxy-hub';
die "already running! ($cmd_dir/ exists)" if (-d $cmd_dir);
mkdir $cmd_dir;

# This will also fork and start any remote tunnels:
my @ssh_cmd = &_get_ssh_cmd(@ARGV);

# If all of the proxy arguments are remote, there is no need to run the local
# ssh server and local forward commands
if(scalar(@ssh_cmd) > 0) {

  qx|/setup_ssh.sh 1>&2|;

  fork || &_loop_fork_exec([qw|/usr/sbin/sshd -D -d|]);
  fork || &_loop_fork_exec([@ssh_cmd]);

  sleep 1;
  print "\n\n --> " . join(' ',@ssh_cmd) . "\n\n";
}


sleep 1 while(1);


##############################################################################
##############################################################################

sub _loop_fork_exec {
  my ($cmd,$sleep) = @_;
  while(1) {
    if(my $pid = fork) {
    
      my $cmd_file = "$cmd_dir/$pid";
      open(my $fh, "> $cmd_file");
      print $fh join(' ',@$cmd) . "\n";
      close($fh);
      
      waitpid($pid,0);
      unlink $cmd_file if (-e $cmd_file);
      
      sleep $sleep if ($sleep);
    }
    else {
      exec @$cmd
    }
  }
}


sub _get_ssh_cmd {
  my @args = @_;
  my $eg = "'<BIND_PORT>:<HOSTNAME>:<PORT>'";
  
  die "No port/proxy ($eg) arguments supplied\n" unless (scalar(@args) > 0);
  
  my @cmd = ();
  
  for my $arg (@args) {
  
    if($arg && $arg =~ /\@/) {
      &_fork_remote_ssh_tunnel($arg);
      next;
    }
  
    my ($local_port,$host,$remote_port) = split(/\:/,$arg);
    die "'$arg' is not a valid port/proxy ($eg) argument\n" unless (
      &_valid_port($local_port) && &_valid_host($host) &_valid_port($remote_port)
    );
    
    push @cmd, '-R', join(':','*',$local_port,$host,$remote_port);
  }
  
  return scalar(@cmd) > 0 
    ? ('ssh', @cmd, '127.0.0.1','-N')
    : ()
}


sub _valid_port {
  my $port = shift;
  return (
    $port && $port =~ /^\d+$/ &&
    $port > 0 && $port < 2**16
  )
}

sub _valid_host {
  my $host = shift;
  return ($host && $host =~ /^[0-9a-z\-\.]+$/i)
}


sub _fork_remote_ssh_tunnel {
  my $arg = shift;
  my $eg = "'<BIND_PORT>:<HOSTNAME>:<PORT>'";
  
  my ($local_port,$host_spec,$remote_port) = split(/\:/,$arg);
  die "'$arg' is not a valid port/proxy ($eg) argument\n" unless (
    &_valid_port($local_port) && &_valid_port($remote_port)
  );

  # read in once per run:
  $client_ids ||= [ &_find_private_id_files($client_id_dir) ];
  
  die join("\n",
    "No valid SSH private keys found in '$client_id_dir'.",
    "cannot setup remote tunnel to '$host_spec'",''
  ) unless(scalar(@$client_ids) > 0);
  
  my ($connect,$farhost) = split(/\^/,$host_spec,2);
  die "bad far hostname '$farhost' (for '$host_spec')" if ($farhost && ! &_valid_host($farhost));
  $farhost ||= '*';
  
  my ($server,$port) = split(/\//,$connect,2);
  die "bad remote ssh port '$port' (for '$host_spec')" if ($port && ! &_valid_port($port));
  $port ||= 22;
  
  my ($user,$host) = split(/\@/,$server,2);
  die "bad remote ssh host '$host' (for '$host_spec')" if ($host && ! &_valid_host($host));
  
  my @cmd = (
    'ssh', 
    '-oPasswordAuthentication=no',
    '-oStrictHostKeyChecking=no',
    '-oAddressFamily=inet', 
    '-p', $port,
    ( map { ('-i', $_) } @$client_ids ),
    '-L', join(':','*',$local_port,$farhost,$remote_port),'-N',
    join('@',$user,$host)
  );

  fork || &_loop_fork_exec(\@cmd,2); 
  print "\n\n --> " . join(' ',@cmd) . "\n\n";
}



sub _find_private_id_files {
  my $dir = shift;
  die "'$dir' not a directory" unless (-d $dir);
  
  my $work_ids = '/var/ids';
  die "Work ids directory '$work_ids' shouldn't already exist, but does" if (-e $work_ids);
  
  my @cmds = (
    "mkdir -p $work_ids",
    "cp $dir/* $work_ids/",
    "cp $dir/.* $work_ids/",
    "chmod 700 $work_ids",
    "chmod 400 $work_ids/*",
    "chmod 400 $work_ids/.*"
  );
  qx|$_ >& /dev/null| for (@cmds);
  
  
  my %seen  = ();
  my @files = ();
  
  my $cwd = getcwd();
  chdir $work_ids;
  foreach my $path ( map { abs_path($_) } glob('.* *') ) {
    if(my $pub = &_is_private_id_file($path)) {
      push @files, $path unless( $seen{$pub}++ );
    }
  }
  chdir $cwd;
  
  return @files;
}

sub _is_private_id_file {
  my $path = shift;
  my $pub = qx|ssh-keygen -P '' -y -f '$path' 2> /dev/null|;
  return $? ? 0 : $pub
}