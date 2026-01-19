# PACS-AI sandbox

This repository contains code and resources to test deployment of PACS-AI on various infrastructures in an organized sandbox. The goal is to
refine the deployment process and provide general recipes for common infrastructures.

## Deployment

1. Run `scripts/01-prerequisites.sh` to install necessary tools.
2. Setup your Google Cloud, Firebase and Mailgun projects as described in the [PACS-AI deployment documentation](https://github.com/HeartWise-AI/pacs-ai-backend?tab=readme-ov-file#2-external-services-setup). Disregard any modifications to the PACS-AI code, this sandbox will handle it. When ask to copy **private keys**, place them in this repository's root, using the same names.
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

4. If deploying PACS-AI in `dev` mode, you'll also need to create a Mailchimp account and fill the following parameters in the `.env` file:

   | Parameter               | Value                                 |
   |-------------------------|---------------------------------------|
   | MAILCHIMP_API_KEY       | Your Mailchimp API key                |
   | MAILCHIMP_LIST_ID       | The ID of the audience/list to subscribe users to |

5. Create the sandbox:
   ```bash
   bash scripts/02-create-sandbox.sh sandbox
   ```

6. Patch the sandbox (fixes Docker networking and permissions):
   ```bash
   bash scripts/03-patch-pacs-ai-sandbox.sh sandbox
   ```

7. Launch the PACS-AI services:
   ```bash
   bash scripts/04-run-sandbox.sh sandbox
   ```

8. Access the application:
   - Frontend: http://localhost:3000
   - API: http://localhost/api
   - API Documentation: http://localhost/api/docs

9. Verify deployment health:
   ```bash
   bash scripts/99-network-test.sh
   ```

## Post-Deployment Configuration

### Configure Hospital DICOM Modalities

After the first deployment, the hospital PACS simulation modalities are registered in Orthanc but need to be configured through the admin UI to enable DICOM query/retrieve/store operations.

**Step-by-step guide:**

1. **Create a tenant owner account** (first-time setup only):
   ```bash
   # Get your Firebase auth token from the browser
   # Then create an owner user with the superuser API:
   curl -X POST http://localhost/api/v1/user/owner/add \
     -H "Content-Type: application/json" \
     -H "X-FB-SUDO-KEY: 12345" \
     -d '{
       "tenantId": "prod-XXXXX",
       "email": "admin@example.com",
       "password": "YourSecurePassword",
       "lastName": "Admin",
       "firstName": "System"
     }'
   ```
   Replace `prod-XXXXX` with your tenant ID from the `.env` file.

2. **Log into the PACS-AI frontend** at http://localhost:3000 with your owner account.

3. **Navigate to the Admin section** (accessible from the top-right user menu).

4. **Go to the Modalities tab** where you'll see three hospital modalities:
   - `hospital-1-query` (HOSPITAL_1_QUERY)
   - `hospital-1-store` (HOSPITAL_1_STORE)
   - `hospital-2` (HOSPITAL_2)

5. **For each modality, click the edit button** (pencil icon) and:
   - ✅ Enable **C-FIND** (DICOM Query)
   - ✅ Enable **C-MOVE** (DICOM Retrieve)
   - ✅ Enable **C-STORE** (DICOM Store)
   - Click **Save**

6. **Verify the configuration**:
   - All three checkboxes should now show as enabled in the modalities list
   - The frontend can now query studies from hospital PACS systems

**What this does:**
- Updates the DICOM permissions in Orthanc (AllowFind, AllowMove, AllowStore)
- Stores the enabled features in Firestore database
- Enables the frontend to perform DICOM query/retrieve operations

**Note:** The modalities are automatically registered in Orthanc during the patch step (step 6), but the DICOM operation flags default to disabled until configured through the UI.

### Upload Sample DICOM Data (Optional)

To populate the hospital PACS simulators with sample studies for testing:

```bash
bash scripts/06-upload-sample-dicom-data.sh
```

This uploads:
- **hospital-1-query**: 3 MRI studies from 2015 (134 DICOM instances)
  - Study dates: 2015-04-13, 2015-05-26
  - Patient: MS (head scans)
- **hospital-2**: 4 sample studies (2000-2001)
  - Includes ultrasound, brain MRI, and PET scans

**Search tips:**
- Use date range 2015-01-01 to 2015-12-31 for hospital-1-query studies
- Use patient ID "MS" to find the MRI studies
- Leave fields empty for broader searches

## Troubleshooting

### PACS-AI server raises `System limit for number of file watchers reached`

If you see this error in the PACS-AI backend logs, increase the number of file watchers on your system by running the following command:

```bash
DESIRED_WATCHES=524288
echo fs.inotify.max_user_watches=$DESIRED_WATCHES | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
```