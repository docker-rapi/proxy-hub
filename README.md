# rapi/proxy-hub

Simple docker image binds local ports proxied to remote host/ports. This
can be useful to be able to expose ports to a docker network for development,
and also just as a general-purpose persistent port proxy.

## Using this image:

The container expects to be called with one or more proxy/port arguments 
of the form:

```
<BIND_PORT>:<HOSTNAME>:<PORT>
```

Where ```<BIND_PORT>``` is the port to bind/listen to on the local container
and ```<HOSTNAME>:<PORT>``` is the remote host and port to proxy to. This is
just based on the format of ssh port forwards (which is what is used internally). 

### persistent proxy

This example command will bind port ```2222``` on the local docker host to
port ```22``` on the remote host ```some-host```: 

```bash
docker run -it --rm -p 2222:2222 rapi/proxy-hub 2222:some-host:22
```
&nbsp;

This is just like setting up an SSH tunnel, except you don't need to login
to anything and it will stay up as long as the container is running.

This allows you to expose proxied ports as a service, for example:

```bash
docker create  \
  --name proxy-svc --hostname=proxy-svc --restart=always \
  -p 2222:2222 -p 3309:3309 -p 3389:3389 \
 rapi/proxy-hub \
  2222:some-host:22 3309:10.23.56.8:3306 3389:windows-box:3389

docker start proxy-svc && docker logs --follow proxy-svc
```

&nbsp;

### proxy for docker networks

You can also use this image to glue-in ports to a docker network to be accessible
from other containers running in that network. For example:

```bash
docker create  \
  --name dbhost --hostname=dbhost --restart=always \
  --net mynet \
rapi/proxy-hub 3306:mysql-server:3306

docker start dbhost
```
&nbsp;

This will allow other containers running in the ```mynet``` docker network to
access the proxied mysql server via the native hostname ```dbhost```
