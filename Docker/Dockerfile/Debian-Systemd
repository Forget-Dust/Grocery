# 构建含systemd的镜像
FROM debian:latest
ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv dbus && apt-get clean && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
CMD []
