FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y
RUN apt-get install -y qemu-system-aarch64 fdisk wget mtools

COPY next_power_of_two.py run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/run.sh /usr/local/bin/next_power_of_two.py

WORKDIR /qemu

EXPOSE 2222

CMD ["/usr/local/bin/run.sh"]
