#!/bin/bash
sudo sh -c 'echo deb https://get.docker.com/ubuntu docker main > /etc/apt/sources.list.d/docker.list'
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9
sudo apt-get update
sudo apt-get install -y apt-transport-https
sudo apt-get install -y lxc-docker
sudo wget -O /usr/local/bin/weave https://github.com/weaveworks/weave/releases/download/latest_release/weave
sudo chmod a+x /usr/local/bin/weave
sudo weave launch 52.28.129.53
IP=10.3.1.$(shuf -i 7-254 -n 1)
sudo weave run --with-dns $IP/24 -h ws.weave.local pessoa/weave-gs-nginx-apache
IP=10.3.1.$(shuf -i 7-254 -n 1)
sudo weave run --with-dns $IP/24 -h ws.weave.local pessoa/weave-gs-nginx-apache
IP=10.3.1.$(shuf -i 7-254 -n 1)
sudo weave run --with-dns $IP/24 -h ws.weave.local pessoa/weave-gs-nginx-apache
