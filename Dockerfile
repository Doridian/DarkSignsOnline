FROM alpine:3.23

ADD https://github.com/nginx/njs-acme/releases/download/v1.0.0/acme.js /etc/nginx/acme.js

RUN apk --no-cache update && \
    apk --no-cache upgrade && \
    apk --no-cache add \
        bash \
        ca-certificates \
        cronie \
        jq \
        libcap \
        nginx \
        nginx-mod-http-js \
        php84-cli \
        php84-fpm \
        php84-json \
        php84-mysqli \
        php84-opcache \
        php84-session \
        s6

RUN setcap cap_net_bind_service=+ep /usr/sbin/nginx && \
    mkdir -p /run/darksignsonline /var/lib/nginx/acme && chown nginx:nginx -R /var/lib/nginx && \
    chmod 444 /etc/nginx/acme.js

ENV HTTP_MODE='http'
ENV DOMAIN='dso'
ENV TRUSTED_PROXIES='127.0.0.1/32 127.0.0.2/32'
COPY LICENSE /var/www/LICENSE

COPY server/rootfs/ /
COPY server/www/ /var/www/

ARG GIT_REVISION="unknown"
RUN echo "${GIT_REVISION}" > /var/www/api/gitrev.txt

ARG CACHE_INVALIDATOR=1
RUN echo "${CACHE_INVALIDATOR}"

ENTRYPOINT [ "/usr/bin/s6-svscan", "/etc/s6" ]
