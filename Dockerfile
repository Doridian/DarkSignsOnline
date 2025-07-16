FROM alpine:3.22

RUN echo '@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing' >> etc/apk/repositories && \
    apk --no-cache update && \
    apk --no-cache upgrade && \
    apk --no-cache add \
        caddy \
        cronie \
        curl \
        jq \
        libcap \
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
    usermod -aG anubis caddy && \
    usermod -aG caddy anubis && \
    setcap cap_net_bind_service=+ep /usr/sbin/caddy && \ 
    mkdir -p /var/lib/caddy && chown caddy:caddy /var/lib/caddy

ENV DOMAIN='http://dso'
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
