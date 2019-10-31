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

my $work_ids = '/var/ids';
my $cmd_dir = '/var/run/proxy-hub';
if($$ == 1) {
  qx|rm -rf $cmd_dir|  if (-d $cmd_dir);
  qx|rm -rf $work_ids| if (-d $work_ids);
}

die "already running! ($cmd_dir/ exists)" if (-d $cmd_dir);
mkdir $cmd_dir;

qx|/setup_ssh.sh 1>&2|;

# This will also fork and start any remote tunnels:
my @ssh_cmd = &_get_ssh_cmd(@ARGV);

# If all of the proxy arguments are remote, there is no need to run the local
# ssh server and local forward commands
if(scalar(@ssh_cmd) > 0) {

  my @sshd_cmd = qw|/usr/sbin/sshd -D|;
  push @sshd_cmd, '-d' if ($ENV{DEBUG} || $ENV{RAPI_PROXY_HUB_DEBUG_LEVEL});
  fork || &_loop_fork_exec([@sshd_cmd]);
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

sub _get_dash_v_arg {
  my $lvl = exists $ENV{RAPI_PROXY_HUB_DEBUG_LEVEL}
    ? $ENV{RAPI_PROXY_HUB_DEBUG_LEVEL} 
    : $ENV{DEBUG} ? 1 : 0;
  
  unless ($lvl =~ /^\d{1}$/) {
    warn "Invalid RAPI_PROXY_HUB_DEBUG_LEVEL '$lvl' - should be number between 0 and 3";
    return ()
  }
  
  return () unless ($lvl > 0);
  return join('','-',('v' x $lvl))
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
  my ($r_host,$r_port) = split(/\~/,$local_port,2);
  if($r_port) {
    $r_host ||= '*';
    $local_port = $r_port if ($r_host eq '*' || &_valid_host($r_host));
  }
  else {
    $r_host = undef;
  }
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
  
  my @tun = $r_host
    ? ('-R', join(':', $r_host, $r_port    , $farhost, $remote_port))
    : ('-L', join(':', '*'    , $local_port, $farhost, $remote_port));
  
  my @cmd = (
    'ssh','-p', $port, ( &_get_dash_v_arg ),
    ( map { ('-i', $_) } @$client_ids ),
    @tun, '-N', join('@',$user,$host)
  );

  fork || &_loop_fork_exec(\@cmd,2); 
  print "\n\n --> " . join(' ',@cmd) . "\n\n";
}



sub _find_private_id_files {
  my $dir = shift;
  die "'$dir' not a directory" unless (-d $dir);
  
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