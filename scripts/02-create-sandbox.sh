#!/usr/bin/env bash

# Download PACS-AI components from github repositories and organize sandbox content
#  - PACS-AI frontend and backend are included as submodules in the repository. The version
#    to install is specified in the .env file.

SANDBOX_PATH=$1

set -e

function merge_dotenv () {
# Merges two .env files into a third file, with variables in file2 taking precedence over file1

local file1=$1
local file2=$2
local file3=$3
sort -u -t '=' -k 1,1 $file2 $file1 | grep -v '^$\|^\s*\#' > $file3

}

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Sync-up submodules to get PACS-AI frontend and backend at specified versions
git submodule update --init
git -C external/pacs-ai-backend checkout "$PACS_AI_BACKEND_VERSION"
git -C external/pacs-ai-frontend checkout "$PACS_AI_FRONTEND_VERSION"
git -C external/pacs-ai-backend pull origin "$PACS_AI_BACKEND_VERSION"
git -C external/pacs-ai-frontend pull origin "$PACS_AI_FRONTEND_VERSION"

if [ $ENVIRONMENT = "dev" ]; then
    echo "Loading PACS-AI submodules recursively for development environment"
    git -C external/pacs-ai-frontend submodule update --init --recursive
fi

echo "PACS-AI components have been downloaded and checked out to specified versions."

# Create sandbox directory structure
mkdir -p $SANDBOX_PATH/pacs-ai-backend
mkdir -p $SANDBOX_PATH/PACS-AI
cp -R external/pacs-ai-backend/. "$SANDBOX_PATH/pacs-ai-backend"
cp -R external/pacs-ai-frontend/. "$SANDBOX_PATH/PACS-AI"

rm -f $SANDBOX_PATH/PACS-AI/platform/app/.env.example
rm -f $SANDBOX_PATH/pacs-ai-backend/api-pacs/.env.example
rm -f $SANDBOX_PATH/pacs-ai-backend/orthanc/.env.example
rm -f $SANDBOX_PATH/pacs-ai-backend/nginx/.env.example

echo "Sandbox directory structure created and sanitized at $SANDBOX_PATH."

# Configuration using environments

if [ $ENVIRONMENT = "prod" ]; then
    merge_dotenv config/.env.prod .env $SANDBOX_PATH/.env.sandbox
else
    merge_dotenv config/.env.dev .env $SANDBOX_PATH/.env.sandbox
fi

export $(grep -v '^#' $SANDBOX_PATH/.env.sandbox | xargs)

echo "Sandbox environment loaded in current shell."

## Configure PACS-AI platform app

cat << EOF > /tmp/platform.env
APP_PUBLIC_API_URL=$API_URL
APP_PUBLIC_DEFAULT_TENANT=$GCP_TENANT_ID
APP_FIREBASE_API_KEY=$FIREBASE_API_KEY
APP_FIREBASE_AUTH_DOMAIN=$FIREBASE_AUTH_DOMAIN
APP_FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
APP_FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET
APP_FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID
APP_FIREBASE_APP_ID=$FIREBASE_APP_ID
APP_FIREBASE_MEASUREMENT_ID=$FIREBASE_MEASUREMENT_ID
EOF

merge_dotenv external/pacs-ai-frontend/platform/app/.env.example /tmp/platform.env \
    $SANDBOX_PATH/PACS-AI/platform/app/.env

echo "PACS-AI platform app configured."

## Configure PACS-AI nginx

cat << EOF > /tmp/nginx.env
SERVER_NAME=$PACS_AI_BACKEND_SERVER
API_KEY=$MAILGUN_API_KEY
EOF

merge_dotenv external/pacs-ai-backend/nginx/.env.example /tmp/nginx.env \
    $SANDBOX_PATH/pacs-ai-backend/nginx/.env

if [ $ENVIRONMENT = "prod" ]; then
    cp $PACS_AI_BACKEND_CERT_FILE_PATH $SANDBOX_PATH/pacs-ai-backend/nginx/ssl/nginx.crt
    cp $PACS_AI_BACKEND_KEY_FILE_PATH $SANDBOX_PATH/pacs-ai-backend/nginx/ssl/nginx.key
fi

echo "PACS-AI nginx configured."

## Configure PACS-AI Orthanc

cat << EOF > /tmp/orthanc.env
ORTHANC_DICOM_AET=$ORTHANC_DICOM_AET
ORTHANC_DICOM_PORT=$ORTHANC_DICOM_PORT
EOF

merge_dotenv external/pacs-ai-backend/orthanc/.env.example /tmp/orthanc.env \
    $SANDBOX_PATH/pacs-ai-backend/orthanc/.env

echo "PACS-AI Orthanc configured."

## Configure PACS-AI API

cp $FIREBASE_CONFIG_FILE_PATH $SANDBOX_PATH/pacs-ai-backend/api-pacs/configs/firebase/pacs-ai-firebase-admin.json

if [ $ENVIRONMENT = "prod" ]; then

echo "not implemented yet !"
exit 1

else

cat << EOF > /tmp/api-pacs.env
API_NAME=$API_NAME
API_URL_REST_PORT=$API_URL_REST_PORT
APP_URL=$APP_URL
CLOUDFLARE_SECRET_KEY=$CLOUDFLARE_SECRET_KEY
CLOUDFLARE_TURNSTILE_BASE_URL=$CLOUDFLARE_TURNSTILE_BASE_URL
DOCKER_USERNAME=$DOCKER_USERNAME
DOCKER_PASSWORD=$DOCKER_PASSWORD
DOCKER_NETWORK=$DOCKER_NETWORK
ELASTICSEARCH_URL=$ELASTICSEARCH_URL
FIREBASE_CONFIG_FILE_PATH=/app/build/configs/firebase/pacs-ai-firebase-admin.json
FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID
FIREBASE_SUPERUSER_KEY=$FIREBASE_SUPERUSER_KEY
KIBANA_BASE_URL=$KIBANA_BASE_URL
MAILCHIMP_API_KEY=$MAILCHIMP_API_KEY
MAILCHIMP_BASE_URL=$MAILCHIMP_BASE_URL
MAILCHIMP_LIST_ID=$MAILCHIMP_LIST_ID
MAILGUN_API_KEY=$MAILGUN_API_KEY
MAILGUN_DOMAIN=$MAILGUN_DOMAIN
MAILGUN_SENDER_EMAIL=$MAILGUN_SENDER_EMAIL
OPENAPI_DOCS_PASSWORD=$OPENAPI_DOCS_PASSWORD
ORTHANC_AET=$ORTHANC_AET
ORTHANC_BASE_URL=$ORTHANC_BASE_URL
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_IAM_DB=$REDIS_IAM_DB
EOF

fi

merge_dotenv external/pacs-ai-backend/api-pacs/.env.example /tmp/api-pacs.env $SANDBOX_PATH/pacs-ai-backend/api-pacs/.env

echo "PACS-AI API configured."

if [ $ENVIRONMENT = "dev" ]; then

echo "Setup local server"

# Verify and install if needed : nvm, npm

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

if ! command -v nvm &> /dev/null
then
    echo "nvm could not be found, installing nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
else
    echo "nvm is already installed."
fi

# Install and use Node.js 18.17.0

nvm install 18.17.0
nvm use 18.17.0

# Install Yarn globally
npm install -g yarn

# Configure Yarn workspaces
yarn config set workspaces-experimental true

CWD=$(pwd)
cd $SANDBOX_PATH/PACS-AI

# Install project dependencies
yarn install

cd $CWD

fi

echo "Sandbox creation completed successfully."
