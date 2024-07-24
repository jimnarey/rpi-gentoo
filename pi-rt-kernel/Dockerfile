FROM ubuntu:24.04

ENV TZ=Europe/London
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && \
    apt-get install -y git bc bison flex libssl-dev make libc6-dev \
    wget libncurses5-dev crossbuild-essential-arm64

RUN apt-get clean && \
    apt-get autoremove && \
    rm -rf /var/lib/apt/lists

COPY build.sh /usr/local/bin/build.sh
RUN chmod a+x /usr/local/bin/build.sh

RUN mkdir /build && \
    chown -R ubuntu:ubuntu /build

WORKDIR /build

USER ubuntu

CMD ["/usr/local/bin/build.sh"]
