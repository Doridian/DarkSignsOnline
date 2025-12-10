#!/usr/bin/env bash

owner="$1"

mkpriv() {
    privfile="${1}"
    touch "${privfile}"
    chown "${owner}" "${privfile}"
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
phpenvvar 'SMTP_HOST'
phpenvvar 'SMTP_FROM'
phpenvvar 'SMTP_USERNAME'
phpenvvar 'SMTP_PASSWORD'
# END Create config.php
