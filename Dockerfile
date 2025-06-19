FROM alpine:3.22 AS builder
RUN apk --no-cache add git

COPY .git /project/.git
RUN git -C /project rev-parse HEAD > /project/gitrev.txt && \
    echo '[]' > /project/releases.json

FROM alpine:3.22

RUN apk --no-cache add \
    caddy \
    php84-fpm \
    php84-gd \
    php84-json \
    php84-mysqli \
    s6 \
    shadow \
    libcap \
    font-roboto

RUN useradd -s /bin/false php && \
    setcap cap_net_bind_service=+ep /usr/sbin/caddy && \ 
    mkdir -p /var/lib/caddy && chown caddy:caddy /var/lib/caddy

COPY server/rootfs/ /
COPY server/www/ /var/www/
COPY LICENSE /var/www/LICENSE
COPY --from=builder /project/gitrev.txt /var/www/api/gitrev.txt
COPY --from=builder /project/releases.json /var/www/releases.json

ENV DOMAIN='http://dso'
ENV CAPTCHA_FONT=/usr/share/fonts/roboto/Roboto-Regular.ttf

ENTRYPOINT [ "/usr/bin/s6-svscan", "/etc/s6" ]
