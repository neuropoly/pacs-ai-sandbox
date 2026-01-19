# Sample DICOM Data

This directory contains sample DICOM studies used for development and testing.

## Structure

```
data/
├── sample-studies/          # Sample DICOM studies
│   ├── study-001/          # Example: Chest X-Ray
│   ├── study-002/          # Example: CT Scan
│   └── study-003/          # Example: MRI
└── README.md               # This file
```

## Usage

In **development mode**, these studies are automatically mounted and made accessible to the Orthanc server through Docker volumes. The mounting process:

1. Uses zero-overhead filesystem access (no data copying)
2. Direct Docker volume mount from host to container
3. Allows Orthanc to access studies at `/data` inside the container

## Adding Your Own Studies

To add custom DICOM studies:

1. Create a new directory under `sample-studies/`
2. Place your DICOM files (`.dcm`) in the directory
3. Restart the sandbox to make them available

**Note**: Do not commit large DICOM files to the repository. Use `.gitignore` to exclude them.
