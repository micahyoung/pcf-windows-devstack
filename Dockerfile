FROM ubuntu:xenial

RUN apt-get update
RUN apt-get install -y ca-certificates curl

VOLUME [/work]

WORKDIR /work
