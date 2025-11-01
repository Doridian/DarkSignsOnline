FROM alpine:3.22

ADD https://github.com/nginx/njs-acme/releases/download/v1.0.0/acme.js /etc/nginx/acme.js

RUN echo '@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> etc/apk/repositories && \
    apk --no-cache update && \
    apk --no-cache upgrade && \
    apk --no-cache add \
        ca-certificates \
        cronie \
        curl \
        jq \
        libcap \
        nginx \
        nginx-mod-http-js \
        msmtp \
        php84-cli \
        php84-ctype \
        php84-dom \
        php84-fileinfo \
        php84-fpm \
        php84-gd \
        php84-iconv \
        php84-intl \
        php84-json \
        php84-mbstring \
        php84-mysqli \
        php84-opcache \
        php84-session \
        php84-xml \
        s6 \
        shadow \
        anubis@testing

RUN useradd -s /bin/false php && \
    useradd -s /bin/false anubis && \
    usermod -aG anubis nginx && \
    usermod -aG nginx anubis && \
    setcap cap_net_bind_service=+ep /usr/sbin/nginx && \
    mkdir -p /var/lib/nginx/acme && chown nginx:nginx -R /var/lib/nginx && \
    chmod 444 /etc/nginx/acme.js

ENV HTTP_MODE='http'
ENV DOMAIN='dso'
COPY LICENSE /var/www/LICENSE

COPY server/rootfs/ /
COPY server/www/ /var/www/

ARG GIT_REVISION="unknown"
RUN echo "${GIT_REVISION}" > /var/www/api/gitrev.txt
RUN ln -s /tmp/releases.json /var/www/releases.json

ARG CACHE_INVALIDATOR=1
RUN echo "${CACHE_INVALIDATOR}"
RUN /bin/refresh_releases.sh /var/www/releases_fallback.json

ENTRYPOINT [ "/usr/bin/s6-svscan", "/etc/s6" ]
