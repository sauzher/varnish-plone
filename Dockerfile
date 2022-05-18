FROM million12/varnish:latest

COPY varnish.vcl /etc/varnish/default.vcl
COPY start.sh /start.sh

ENV VCL_CONFIG      /etc/varnish/default.vcl
ENV CACHE_SIZE      64m
ENV BACKEND         127.0.0.1
ENV BACKEND_PORT    8080
ENV PURGE_SERVERS   ""
ENV VARNISHD_PARAMS -p default_ttl=3600 -p default_grace=3600

CMD /start.sh
EXPOSE 80