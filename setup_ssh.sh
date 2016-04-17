#!/bin/sh

if [ $RAPI_PROXY_HUB_DOCKERIZED ] && [ ! -d /root/.ssh ]; then
  ssh-keygen -t dsa     -f /etc/ssh/ssh_host_dsa_key     -N ''
  ssh-keygen -t rsa     -f /etc/ssh/ssh_host_rsa_key     -N ''
  ssh-keygen -t ecdsa   -f /etc/ssh/ssh_host_ecdsa_key   -N ''
  ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''
  
  ssh-keygen -t rsa -f /root/.ssh/id_rsa -N ''
  cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
  
  known_hostname='127.0.0.1'
  
  echo "$known_hostname $(cat /etc/ssh/ssh_host_dsa_key.pub)"     >> /root/.ssh/known_hosts
  echo "$known_hostname $(cat /etc/ssh/ssh_host_rsa_key.pub)"     >> /root/.ssh/known_hosts
  echo "$known_hostname $(cat /etc/ssh/ssh_host_ecdsa_key.pub)"   >> /root/.ssh/known_hosts
  echo "$known_hostname $(cat /etc/ssh/ssh_host_ed25519_key.pub)" >> /root/.ssh/known_hosts
  
  echo -e "\n\nGatewayPorts yes" >> /etc/ssh/sshd_config
fi
