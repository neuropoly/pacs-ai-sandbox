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
    
    # Optionally reload test data if requested
    if [ "$RELOAD_TESTDATA" = "true" ]; then
        echo "Reloading test data from external repositories..."
        if bash scripts/05-load-testdata.sh "$SANDBOX_PATH"; then
            echo "Test data reloaded successfully"
        else
            echo "⚠ Warning: Test data reload failed or was skipped"
        fi
    fi

    CWD=$(pwd)
    cd $SANDBOX_PATH/PACS-AI

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    nvm use 18.17.0
    yarn start &
    cd $CWD
    echo "PACS-AI server running at http://localhost:3000"

    echo "Starting PACS-AI backend"
    cd $SANDBOX_PATH/pacs-ai-backend
    make up &
    BACKEND_PID=$!
    
    # Wait for containers to start, then upload testdata
    echo "Waiting for containers to start (30 seconds)..."
    sleep 30
    
    cd $CWD
    echo "Uploading test data to hospital PACS containers..."
    if bash scripts/05-load-testdata.sh "$SANDBOX_PATH"; then
        echo "✓ Test data uploaded successfully"
    else
        echo "⚠ Test data upload incomplete - you can retry with:"
        echo "  bash scripts/05-load-testdata.sh $SANDBOX_PATH"
    fi
    
    # Wait for backend to finish (it won't, but this keeps the script running)
    wait $BACKEND_PID
else
    echo "Starting PACS-AI backend"
    cd $SANDBOX_PATH/pacs-ai-backend
    make up-prod
fi

