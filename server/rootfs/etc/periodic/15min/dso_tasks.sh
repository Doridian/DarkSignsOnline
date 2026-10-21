#!/bin/sh
set -e

s6-setuidgid nginx /usr/bin/darksignsonline-server tasks
