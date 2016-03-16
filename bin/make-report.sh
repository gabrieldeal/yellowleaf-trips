#!/usr/bin/bash
umask 0022;cd ~/projects/yellowleaf-trips && perl bin/make-report "$@" fuck-line-feeds
