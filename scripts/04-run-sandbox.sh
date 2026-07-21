#!/usr/bin/env bash

# Launch the PACS-AI sandbox environment using Docker Compose

SANDBOX_PATH=$1

set -e

# Load environment variables from sandbox .env file
export $(grep -v '^#' $SANDBOX_PATH/.env.sandbox | xargs)

# Ignite docker network

docker network inspect pacs-net >/dev/null 2>&1 || \
    docker network create pacs-net

if [ $ENVIRONMENT = "dev" ]; then
    echo "Starting PACS-AI development server"

    CWD=$(pwd)

    echo "Starting PACS-AI backend"
    cd $SANDBOX_PATH/pacs-ai-backend
    make up

    cd $CWD
    cd $SANDBOX_PATH/PACS-AI

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    nvm use 20.20.2
    yarn start &
    cd $CWD

    echo "PACS-AI server running at http://localhost:3000"

else
    echo "Starting PACS-AI backend"
    cd $SANDBOX_PATH/pacs-ai-backend
    make up-prod
fi

