#!/usr/bin/env bash

apt-get --yes autoremove
apt-get clean
journalctl --vacuum-time=7days
