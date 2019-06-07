#!/bin/bash
# Install docker and docker-compose

sudo dnf -y install dnf-plugins-core
sudo dnf -y install dnf-plugins-core


echo "[INFO] Installing DOCKER"
# Install the dnf-plugins-core package which provides the commands to manage your DNF repositories from the command line.
sudo dnf -y install dnf-plugins-core

# Use the following command to set up the stable repository.
sudo dnf config-manager \
  --add-repo \
  https://download.docker.com/linux/fedora/docker-ce.repo

# Install the latest version of Docker CE and containerd, or go to the next step to install a specific version:
sudo dnf install docker-ce docker-ce-cli containerd.io

# Enable and start docker service
sudo systemctl enable docker && \
  systemctl start docker

echo -e "[INFO] Docker installed. Add you user to docker group\n
sudo usermod -aG docker your-user"

echo "[INFO] Installing docker-compose"
# Run this command to download the current stable release of Docker Compose:
sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
# Apply executable permissions to the binary:
sudo chmod +x /usr/local/bin/docker-compose


