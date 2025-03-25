#!/bin/ksh
PATH=/usr/linux/bin:/bin:/usr/bin:$PATH
df -lP | grep -v proc

