#!/bin/sh
ln -s cpu,cpuacct /sys/fs/cgroup/cpu
ln -s cpu,cpuacct /sys/fs/cgroup/cpuacct
exec /opt/go-judge -http-addr 0.0.0.0:5050
