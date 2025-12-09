#!/usr/bin/env bash

mkpriv() {
    privfile="${1}"
    touch "${privfile}"
    chown root:php "${privfile}" || true
    chmod 640 "${privfile}"
}

# BEGIN Create config.php
PRIVCONF=/run/darksignsonline/dso-config.php
mkpriv "${PRIVCONF}"

phpenvvar() {
    VAR="${1}"
    eval VAL="\$$VAR"
    echo "\$${VAR} = '${VAL}';" >> "${PRIVCONF}"
}

phpenvvar_b64() {
    VAR="${1}"
    eval VAL="\$$VAR"
    echo "\$${VAR} = base64_decode('${VAL}');" >> "${PRIVCONF}"
}

echo '<?php' > "${PRIVCONF}"
phpenvvar 'MYSQL_HOST'
phpenvvar 'MYSQL_USERNAME'
phpenvvar 'MYSQL_PASSWORD'
phpenvvar 'MYSQL_DATABASE'
phpenvvar_b64 'JWT_PRIVATE_KEY'
phpenvvar_b64 'JWT_PUBLIC_KEY'

echo "<?php require_once('${PRIVCONF}');" > /var/www/api/config.php
# END Create config.php

# BEGIN Create msmtp config
MSMTP_CONF=/run/darksignsonline/msmtp.conf
mkpriv "${MSMTP_CONF}"
MSMTP_PASSWD=/run/darksignsonline/msmtp.passwd
mkpriv "${MSMTP_PASSWD}"

echo 'defaults' > "${MSMTP_CONF}"
echo 'auth on' >> "${MSMTP_CONF}"
echo 'tls on' >> "${MSMTP_CONF}"
echo 'tls_starttls on' >> "${MSMTP_CONF}"
echo "port 587" >> "${MSMTP_CONF}"
echo 'account default' >> "${MSMTP_CONF}"
echo "host ${SMTP_HOST}" >> "${MSMTP_CONF}"
echo "from ${SMTP_FROM}" >> "${MSMTP_CONF}"
echo "user ${SMTP_USERNAME}" >> "${MSMTP_CONF}"
echo "passwordeval cat '${MSMTP_PASSWD}'" >> "${MSMTP_CONF}"

echo "${SMTP_PASSWORD}" > "${MSMTP_PASSWD}"
# END Create msmtp config
