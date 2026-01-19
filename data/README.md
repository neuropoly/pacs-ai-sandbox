# Sample DICOM and DICOMweb Data

This directory contains sample medical imaging data used for development and testing.

## Structure

```
data/
├── sample-studies/                    # Sample DICOM studies
│   ├── study-001/                    # Your custom studies
│   ├── study-002/                    # Your custom studies
│   ├── study-003/                    # Your custom studies
│   └── testdata-from-external/       # Auto-loaded from external repos
└── README.md                         # This file
```

## Automatic Test Data Loading

In **development mode**, the sandbox automatically loads test data from external PACS-AI repositories:

### DICOMweb Test Data
- **Source**: `external/pacs-ai-frontend/platform/app/public/testdata/`
- **Destination**: Copied to `sandbox/PACS-AI/platform/app/public/testdata/`
- **Access**: Served by the frontend application at runtime
- **Purpose**: Pre-configured DICOMweb studies for immediate testing

### DICOM Test Files
- **Source**: Testdata directories in external repositories
- **Destination**: `data/sample-studies/testdata-from-external/`
- **Access**: Mounted to Orthanc container at `/data/testdata-from-external/`
- **Purpose**: DICOM files for Orthanc testing

### Reloading External Test Data

To manually reload test data from external repositories:
```bash
bash scripts/05-load-testdata.sh sandbox
```

## Custom Local DICOM Data

### Usage

Your custom studies are automatically mounted and made accessible to the Orthanc server through Docker volumes:

1. Uses zero-overhead filesystem access (no data copying)
2. Direct Docker volume mount from host to container
3. Allows Orthanc to access studies at `/data` inside the container

### Adding Your Own Studies

To add custom DICOM studies:

1. Create a new directory under `sample-studies/`
2. Place your DICOM files (`.dcm`) in the directory
3. Verify with: `bash scripts/98-validate-local-data.sh`
4. Restart the sandbox to make them available

**Note**: Do not commit large DICOM files to the repository. Use `.gitignore` to exclude them.

## Validation

Run the validation script to check your local data configuration:
```bash
bash scripts/98-validate-local-data.sh
```

