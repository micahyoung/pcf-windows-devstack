FROM ubuntu:xenial

RUN apt-get update
RUN apt-get install -y ca-certificates

VOLUME [/work]

WORKDIR /work
