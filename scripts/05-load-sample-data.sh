#!/usr/bin/env bash

# Load sample DICOM data into Orthanc server
# This script provides utilities to check DICOM files in the data/sample-studies directory
# and verify Orthanc connectivity for testing and development.

ORTHANC_URL=${1:-"http://localhost:8053"}

set -e

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$REPO_ROOT/data/sample-studies"

echo "=========================================="
echo "PACS-AI Sample Data Loader"
echo "=========================================="
echo ""
echo "This script helps verify sample DICOM data configuration."
echo ""

# Check if data directory exists
if [ ! -d "$DATA_DIR" ]; then
    echo "Error: $DATA_DIR directory not found"
    exit 1
fi

# Count DICOM files
DICOM_COUNT=$(find "$DATA_DIR" -name "*.dcm" 2>/dev/null | wc -l)

if [ "$DICOM_COUNT" -eq 0 ]; then
    echo "No DICOM files found in $DATA_DIR"
    echo ""
    echo "To add sample data:"
    echo "  1. Place your .dcm files in data/sample-studies/"
    echo "  2. Organize them in subdirectories (e.g., study-001/, study-002/)"
    echo "  3. Run this script again"
    echo ""
    echo "You can download sample DICOM data from:"
    echo "  - https://www.rubomedical.com/dicom_files/"
    echo "  - https://www.cancerimagingarchive.net/"
    echo ""
    exit 0
fi

echo "Found $DICOM_COUNT DICOM files"
echo ""

# Check if Orthanc is accessible
if command -v curl &> /dev/null; then
    echo "Checking Orthanc connectivity at $ORTHANC_URL..."
    if curl -s -f "$ORTHANC_URL/system" > /dev/null 2>&1; then
        echo "✓ Orthanc is accessible"
    else
        echo "⚠ Warning: Could not connect to Orthanc at $ORTHANC_URL"
        echo "  Make sure the PACS-AI backend is running (scripts/04-run-sandbox.sh)"
    fi
    echo ""
fi

echo "Sample data is ready and will be accessible through the mounted volume."
echo ""
echo "To manually import DICOM files into Orthanc:"
echo "  1. Access Orthanc UI at $ORTHANC_URL"
echo "  2. Use the 'Upload' feature in the web interface"
echo "  3. Or use DICOM C-STORE to push files to Orthanc"
echo ""
echo "For automatic import, the data is mounted at /data in the Orthanc container."
echo ""
