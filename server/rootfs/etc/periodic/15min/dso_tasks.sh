#!/bin/sh
set -e

s6-setuidgid nginx php84 /var/www/_tasks.php
