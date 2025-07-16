#!/bin/sh
set -e

s6-setuidgid php /bin/refresh_releases.sh
