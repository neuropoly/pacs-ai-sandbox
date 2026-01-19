# PACS-AI Sandbox

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Environment](https://img.shields.io/badge/environment-dev%20%7C%20prod-green.svg)
![Docker](https://img.shields.io/badge/docker-compose%20v2.24.7%2B-blue.svg)
![Status](https://img.shields.io/badge/status-active-success.svg)

This repository contains code and resources to test deployment of PACS-AI on various infrastructures in an organized sandbox. The goal is to unify the deployment process and provide general recipes for common infrastructures.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
  - [External Services Setup](#external-services-setup)
  - [Environment Configuration](#environment-configuration)
  - [Sandbox Creation](#sandbox-creation)
  - [Launch Services](#launch-services)
- [Development Features](#development-features)
  - [Sample DICOM Data](#sample-dicom-data)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)

## Overview

PACS-AI Sandbox provides a unified deployment environment for the PACS-AI platform, supporting both development and production modes. The sandbox includes:

- **PACS-AI Frontend**: Web application for medical image viewing and AI analysis
- **PACS-AI Backend**: RESTful API server with authentication and AI processing
- **Orthanc DICOM Server**: Medical image storage and DICOM networking
- **Hospital PACS Simulation** (dev mode): Multiple Orthanc instances simulating real-world hospital PACS systems
- **Sample DICOM Data** (dev mode): Pre-loaded medical imaging studies for testing

## Prerequisites

Before starting, ensure you have the required tools installed by running:

```bash
bash scripts/01-prerequisites.sh
```

This will install:
- Docker + Docker Compose (>= v2.24.7)
- make

## Deployment

### External Services Setup

1. Setup your Google Cloud, Firebase and Mailgun projects as described in the [PACS-AI deployment documentation](https://github.com/HeartWise-AI/pacs-ai-backend?tab=readme-ov-file#2-external-services-setup). 

   **Important**: Disregard any modifications to the PACS-AI code mentioned in the documentation - this sandbox handles all necessary patches automatically.
   
   When asked to copy **private keys**, place them in this repository's root, using the same names.

2. If deploying in **development mode**, also register:
   - **Mailchimp** account (for email subscriptions)
   - **Cloudflare** account (for bot protection)

### Environment Configuration

3. Fill the environment file (`.env`) with the required configuration

   From the Google Cloud Console, find the `prod` tenant created for PACS-AI and copy its ID (`prod-***`) to the
   `GCP_TENANT_ID` parameter in the `.env` file.

   Then, on Firebase, navigate to the webapp created and find its configuration :

   ```js
   const firebaseConfig = {
     apiKey: "***",
     authDomain: "***",
     projectId: "***",
     storageBucket: "***",
     messagingSenderId: "***",
     appId: "***"
   };
   ```

   fill up the `.env` file as follows:

   | Parameter                    | Value                     |
   |------------------------------|---------------------------|
   | FIREBASE_API_KEY             | apiKey                    |
   | FIREBASE_AUTH_DOMAIN         | authDomain                |
   | FIREBASE_PROJECT_ID          | projectId                 |
   | FIREBASE_STORAGE_BUCKET      | storageBucket             |
   | FIREBASE_MESSAGING_SENDER_ID | messagingSenderId         |
   | FIREBASE_APP_ID              | appId                     |

   Finally, create an API key on Mailgun and copy it to `MAILGUN_API_KEY`.

4. If deploying PACS-AI in `dev` mode, you'll also need to create Mailchimp and Cloudflare
   accounts and fill the following parameters in the `.env` file:

   | Parameter               | Value                                 |
   |-------------------------|---------------------------------------|
   | MAILCHIMP_API_KEY       | Your Mailchimp API key                |
   | MAILCHIMP_LIST_ID       | The ID of the audience/list to subscribe users to |
   | CLOUDFLARE_SECRET_KEY   | Your Cloudflare API token             |

### Sandbox Creation

5. Create the sandbox:
   ```bash
   bash scripts/02-create-sandbox.sh sandbox
   ```

6. Patch the sandbox (fixes Docker networking, permissions, and configures development features):
   ```bash
   bash scripts/03-patch-pacs-ai-sandbox.sh sandbox
   ```

### Launch Services

7. Launch the PACS-AI services:
   ```bash
   bash scripts/04-run-sandbox.sh sandbox
   ```

## Development Features

### Sample DICOM Data

In **development mode**, the sandbox provides a zero-overhead mechanism to access sample DICOM studies for testing:

- **Zero-overhead mounting**: Sample studies are directly mounted into the Orthanc container via Docker volumes
- **No data copying**: Direct filesystem access without duplication
- **Automatic configuration**: Volume mount is configured during sandbox patching
- **Easy access**: Files are available at `/data` inside the Orthanc container

#### Adding Sample Data

1. Place your DICOM files (`.dcm`) in the `data/sample-studies/` directory:
   ```bash
   # Organize by study
   data/sample-studies/study-001/*.dcm
   data/sample-studies/study-002/*.dcm
   ```

2. Run the data loader helper script (optional, for verification):
   ```bash
   bash scripts/05-load-sample-data.sh sandbox
   ```

3. Access the data through Orthanc's web interface or API

**Note**: DICOM files are excluded from git by default to avoid repository bloat. You can download sample DICOM data from:
- [RuboMedical DICOM Files](https://www.rubomedical.com/dicom_files/)
- [The Cancer Imaging Archive](https://www.cancerimagingarchive.net/)

## Accessing Services

8. Access the application:
   - Frontend: http://localhost:3000
   - API: http://localhost/api
   - API Documentation: http://localhost/api/docs
   - Orthanc (Main PACS): http://localhost:8053
   - Orthanc Hospital 1 (Query): http://localhost:8063 (dev mode)
   - Orthanc Hospital 1 (Store): http://localhost:8073 (dev mode)
   - Orthanc Hospital 2: http://localhost:8083 (dev mode)

9. Verify deployment health:
   ```bash
   bash scripts/99-network-test.sh
   ```

## Troubleshooting

### PACS-AI server raises `System limit for number of file watchers reached`

If you see this error in the PACS-AI backend logs, increase the number of file watchers on your system by running the following command:

```bash
DESIRED_WATCHES=524288
echo fs.inotify.max_user_watches=$DESIRED_WATCHES | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
```