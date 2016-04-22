FROM alpine:3.3
MAINTAINER Henry Van Styn <vanstyn@cpan.org>

RUN apk add --update \
  openssh \
  perl \
  bash \
&& rm -rf /var/cache/apk/* \
&& mkdir -p /opt/ids

# env flag used by CMD script to prevent running except from here
ENV RAPI_PROXY_HUB_DOCKERIZED 1

ENTRYPOINT ["/entrypoint.pl"]

COPY setup_ssh.sh /
COPY entrypoint.pl /
