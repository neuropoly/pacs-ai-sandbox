# Launching platform in production

This document outlines the steps and additional requirements for launching the PACS-AI platform in
a production environment. It is based on the same set of environment files and
scripts used for development.

## Prerequisites

## Production environment

First, comment the `development only configuration` section in the `.env` file and uncomment the `production only configuration` section. Then, fill the following sections, from the top :

### Sandbox type

Switch it to `prod`.

### Docker authentication

Set `DOCKER_USERNAME` to your Docker Hub username, and `DOCKER_PASSWORD` to a [personal access token](https://docs.docker.com/docker-hub/access-tokens/) you created on Docker Hub. It will be used to pull container updates for models and
the platform itself.

### Open API documentation

Set the `OPENAPI_DOCS_PASSWORD` variable to a strong password. It will be used to protect access to the Open API documentation of the platform.

### ORTHANC dicom connection

Set the `ORTHANC_DICOM_AET` variable and `ORTHANC_DICOM_PORT` following your
Orthanc DICOM configuration. These values will be used by the platform to
connect to Orthanc and retrieve DICOM images.

### PACS-AI Backend server

Set `PACS_AI_BACKEND_SERVER` to the address of your dedicated PACS-AI Backend server. Also get a **certificate** and its **private key** for HTTPS connections and set `PACS_AI_BACKEND_CERT_FILE_PATH` and `PACS_AI_BACKEND_KEY_FILE_PATH` to their respective file paths.

### Domain hosting the UI

Set `APP_URL` to the domain name provided to host the PACS-AI Frontend application and set `API_URL` to the same value, suffixed with `/api` (e.g. `https://your-domain.com/api`), if hosting the API on the same domain. Else, set `API_URL` to its domain name.

## Production deployment

Here, time to run scripts `02` and `04` skipping `03`, as no patch is needed for production.

``sh
bash scripts/02-create-sandbox.sh prod
bash scripts/04-run-sandbox.sh prod
``
