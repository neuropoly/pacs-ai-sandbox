# PACS-AI sandbox

This repository contains code and resources to test deployment of PACS-AI on various infrastructures in an organized sandbox. The goal is to
refine the deployment process and provide general recipes for common infrastructures.

## Deployment

1. Run `scripts/01-prerequisites.sh` to install necessary tools.
2. Setup your Google Cloud, Firebase and Mailgun projects as described in the [PACS-AI deployment documentation](https://github.com/HeartWise-AI/pacs-ai-backend?tab=readme-ov-file#2-external-services-setup). Disregard any modifications to the PACS-AI code, this sandbox will handle it. When ask to copy **private keys**, place them in this repository's root, using the same names.
3. Fill the environment file with the required configuration

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

4. If deploying PACS-AI in `dev` mode, you'll also need to create a Mailchimp account and fill the following parameters in the `.env` file:

   | Parameter               | Value                                 |
   |-------------------------|---------------------------------------|
   | MAILCHIMP_API_KEY       | Your Mailchimp API key                |
   | MAILCHIMP_LIST_ID       | The ID of the audience/list to subscribe users to |