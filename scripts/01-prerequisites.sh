#!/usr/bin/env bash

# Deploy prerequisites for PACS-AI
#  - Docker + compose >= v2.24.7
#  - make


set -e

# Verify Docker installation. If docker is installed, verify it has compose.
# Then verify compose version. If either not installed or version is insufficient,
# install/upgrade Docker. We take into account we are on Ubuntu based distro.
DOCKER_INSTALLED=$(command -v docker || true)

if [ -z "$DOCKER_INSTALLED" ] ; then
    echo "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    DOCKER_COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || true)
    if [ -z "$DOCKER_COMPOSE_VERSION" ] || [ "$(printf '%s\n%s\n' "2.24.7" "$DOCKER_COMPOSE_VERSION" | sort -V | head -n1)" != "2.24.7" ]; then
        echo "Docker Compose version is insufficient or not found. Upgrading Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
    else
        echo "Docker and Docker Compose are already installed and meet version requirements."
    fi
fi

# Verify make installation
MAKE_INSTALLED=$(command -v make || true)

if [ -z "$MAKE_INSTALLED" ] ; then
    echo "make not found. Installing make... the script might ask for elevation of privileges."
    sudo apt-get update
    sudo apt-get install -y make
else
    echo "make is already installed."
fi

echo "All prerequisites are installed."
