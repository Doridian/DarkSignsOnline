FROM alpine:3.22

RUN apk --no-cache add \
    caddy \
    php84-fpm \
    php84-cli \
    php84-dom \
    php84-gd \
    php84-json \
    php84-mysqli \
    php84-session \
    php84-opcache \
    php84-mbstring \
    php84-xml \
    php84-ctype \
    php84-iconv \
    php84-fileinfo \
    php84-intl \
    s6 \
    msmtp \
    shadow \
    libcap \
    font-roboto

RUN useradd -s /bin/false php && \
    setcap cap_net_bind_service=+ep /usr/sbin/caddy && \ 
    mkdir -p /var/lib/caddy && chown caddy:caddy /var/lib/caddy

ENV DOMAIN='http://dso'
ENV CAPTCHA_FONT=/usr/share/fonts/roboto/Roboto-Regular.ttf
COPY LICENSE /var/www/LICENSE

COPY server/rootfs/ /
COPY server/www/ /var/www/

ARG GIT_REVISION="unknown"
RUN echo "${GIT_REVISION}" > /var/www/api/gitrev.txt
RUN echo '[]' > /var/www/releases.json

ENTRYPOINT [ "/usr/bin/s6-svscan", "/etc/s6" ]
