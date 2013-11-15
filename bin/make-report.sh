#!/usr/bin/bash
umask 0022;cd ~/scramble && perl bin/make-report "$@" fuck-line-feeds
