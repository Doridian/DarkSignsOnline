#!/bin/sh
set -e

s6-setuidgid php php84 /var/www/_tasks.php
