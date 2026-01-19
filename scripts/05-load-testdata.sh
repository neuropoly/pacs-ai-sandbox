#!/usr/bin/env bash

# Load sample test data from external PACS-AI repositories
# This script copies/links DICOM and DICOMweb test data from the external
# pacs-ai-frontend testdata directory to make them available in the sandbox.

SANDBOX_PATH=$1

# Note: We don't use 'set -e' here to allow graceful handling of missing directories

if [ -z "$SANDBOX_PATH" ]; then
    echo "Error: SANDBOX_PATH argument is required"
    echo "Usage: bash scripts/05-load-testdata.sh <sandbox-path>"
    exit 1
fi

if [ ! -d "$SANDBOX_PATH" ]; then
    echo "Error: Sandbox path does not exist: $SANDBOX_PATH"
    exit 1
fi

echo "=========================================="
echo "Loading Test Data from PACS-AI"
echo "=========================================="
echo ""

# Get the repository root
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

# Load environment to check if we're in dev mode (in a subshell to avoid affecting parent)
ENVIRONMENT=""
if [ -f "$SANDBOX_PATH/.env.sandbox" ]; then
    ENVIRONMENT=$(grep -E '^[[:space:]]*ENVIRONMENT=' "$SANDBOX_PATH/.env.sandbox" | cut -d'=' -f2- | tr -d ' "' || echo "")
fi

if [ "$ENVIRONMENT" != "dev" ]; then
    echo "ℹ Test data loading is only active in development mode"
    echo "Current environment: ${ENVIRONMENT:-not set}"
    exit 0
fi

echo "1. Loading DICOM test data from external repositories..."

# Check if external pacs-ai-frontend has testdata
FRONTEND_TESTDATA="$REPO_ROOT/external/pacs-ai-frontend/platform/app/public/testdata"

if [ ! -d "$FRONTEND_TESTDATA" ]; then
    echo "   ⚠ Frontend testdata directory not found at: $FRONTEND_TESTDATA"
    echo "   Trying alternative path..."
    
    # Try alternative paths
    FRONTEND_TESTDATA="$REPO_ROOT/external/pacs-ai-frontend/testdata"
    
    if [ ! -d "$FRONTEND_TESTDATA" ]; then
        echo "   ⚠ No testdata found in pacs-ai-frontend"
        echo "   Skipping testdata loading"
        FRONTEND_TESTDATA=""
    fi
fi

if [ -n "$FRONTEND_TESTDATA" ] && [ -d "$FRONTEND_TESTDATA" ]; then
    echo "   ✓ Found testdata at: $FRONTEND_TESTDATA"
    
    # Create testdata directory in local data folder
    mkdir -p "$REPO_ROOT/data/sample-studies/testdata-from-external"
    
    # Check what's in the testdata directory
    DICOM_FILES=$(find "$FRONTEND_TESTDATA" -name "*.dcm" 2>/dev/null | wc -l)
    DICOMWEB_DIRS=$(find "$FRONTEND_TESTDATA" -type d -name "*dicomweb*" -o -name "*DICOMweb*" 2>/dev/null | wc -l)
    
    echo "   ℹ Found $DICOM_FILES DICOM files"
    echo "   ℹ Found $DICOMWEB_DIRS DICOMweb directories"
    
    if [ "$DICOM_FILES" -gt 0 ] || [ "$DICOMWEB_DIRS" -gt 0 ]; then
        # Copy or symlink the testdata
        echo "   → Copying testdata to local data directory..."
        
        # Copy DICOM files
        if [ "$DICOM_FILES" -gt 0 ]; then
            find "$FRONTEND_TESTDATA" -name "*.dcm" -exec cp {} "$REPO_ROOT/data/sample-studies/testdata-from-external/" \; 2>/dev/null || true
            echo "   ✓ Copied DICOM files to data/sample-studies/testdata-from-external/"
        fi
        
        # Handle DICOMweb data - these should be accessible to the frontend
        if [ "$DICOMWEB_DIRS" -gt 0 ]; then
            # Create a symlink or copy DICOMweb data to the sandbox frontend
            SANDBOX_FRONTEND="$SANDBOX_PATH/PACS-AI/platform/app/public"
            
            if [ -d "$SANDBOX_FRONTEND" ]; then
                # Ensure testdata directory exists in sandbox
                mkdir -p "$SANDBOX_FRONTEND/testdata"
                
                # Copy DICOMweb data
                echo "   → Copying DICOMweb testdata to sandbox frontend..."
                cp -R "$FRONTEND_TESTDATA"/. "$SANDBOX_FRONTEND/testdata/" 2>/dev/null || true
                echo "   ✓ DICOMweb data available at sandbox/PACS-AI/platform/app/public/testdata/"
            else
                echo "   ⚠ Sandbox frontend public directory not found"
            fi
        fi
    fi
else
    echo "   ℹ No testdata directory found in external dependencies"
fi

echo ""

echo "2. Checking backend test data..."

BACKEND_TESTDATA="$REPO_ROOT/external/pacs-ai-backend/testdata"

if [ -d "$BACKEND_TESTDATA" ]; then
    echo "   ✓ Found backend testdata at: $BACKEND_TESTDATA"
    
    BACKEND_DICOM=$(find "$BACKEND_TESTDATA" -name "*.dcm" 2>/dev/null | wc -l)
    echo "   ℹ Found $BACKEND_DICOM DICOM files"
    
    if [ "$BACKEND_DICOM" -gt 0 ]; then
        find "$BACKEND_TESTDATA" -name "*.dcm" -exec cp {} "$REPO_ROOT/data/sample-studies/testdata-from-external/" \; 2>/dev/null || true
        echo "   ✓ Copied backend DICOM files"
    fi
else
    echo "   ℹ No backend testdata directory found"
fi

echo ""
echo "=========================================="
echo "Test Data Loading Complete"
echo "=========================================="
echo ""

# Ensure the directory exists before counting
mkdir -p "$REPO_ROOT/data/sample-studies/testdata-from-external"

# Count total files loaded
TOTAL_DICOM=$(find "$REPO_ROOT/data/sample-studies/testdata-from-external" -name "*.dcm" 2>/dev/null | wc -l || echo "0")

if [ "$TOTAL_DICOM" -gt 0 ]; then
    echo "✓ Successfully loaded $TOTAL_DICOM DICOM files from external testdata"
    echo ""
    echo "DICOM files location:"
    echo "  → data/sample-studies/testdata-from-external/"
    echo "  → Will be mounted to Orthanc at /data/testdata-from-external/"
else
    echo "ℹ No DICOM files were loaded from external testdata"
    echo ""
    echo "This is normal if:"
    echo "  - External repositories don't contain testdata directories"
    echo "  - Submodules haven't been initialized yet"
    echo "  - You're using custom test data"
fi

echo ""
echo "Note: DICOMweb data (if found) is copied to:"
echo "  → $SANDBOX_PATH/PACS-AI/platform/app/public/testdata/"
echo ""

# Upload DICOM files to hospital PACS containers if they're running
if [ "$TOTAL_DICOM" -gt 0 ]; then
    echo "Attempting to upload DICOM files to hospital PACS containers..."
    echo ""
    
    # Check if we can reach the hospital PACS containers
    # These are typically at localhost:8063, 8073, 8083 when running
    
    UPLOADED=false
    
    # Try uploading to orthanc-hospital-1-store (port 8073)
    if command -v curl &> /dev/null; then
        if curl -s -f "http://localhost:8073/system" > /dev/null 2>&1; then
            echo "  → Uploading to orthanc-hospital-1-store (http://localhost:8073)..."
            UPLOAD_COUNT=0
            for dcm_file in "$REPO_ROOT/data/sample-studies/testdata-from-external"/*.dcm; do
                if [ -f "$dcm_file" ]; then
                    if curl -s -X POST "http://localhost:8073/instances" \
                        -H "Content-Type: application/dicom" \
                        --data-binary "@$dcm_file" > /dev/null 2>&1; then
                        ((UPLOAD_COUNT++))
                    fi
                fi
            done
            if [ "$UPLOAD_COUNT" -gt 0 ]; then
                echo "    ✓ Uploaded $UPLOAD_COUNT DICOM files to orthanc-hospital-1-store"
                UPLOADED=true
            fi
        fi
        
        # Try uploading to orthanc-hospital-2 (port 8083)
        if curl -s -f "http://localhost:8083/system" > /dev/null 2>&1; then
            echo "  → Uploading to orthanc-hospital-2 (http://localhost:8083)..."
            UPLOAD_COUNT=0
            for dcm_file in "$REPO_ROOT/data/sample-studies/testdata-from-external"/*.dcm; do
                if [ -f "$dcm_file" ]; then
                    if curl -s -X POST "http://localhost:8083/instances" \
                        -H "Content-Type: application/dicom" \
                        --data-binary "@$dcm_file" > /dev/null 2>&1; then
                        ((UPLOAD_COUNT++))
                    fi
                fi
            done
            if [ "$UPLOAD_COUNT" -gt 0 ]; then
                echo "    ✓ Uploaded $UPLOAD_COUNT DICOM files to orthanc-hospital-2"
                UPLOADED=true
            fi
        fi
    fi
    
    if [ "$UPLOADED" = false ]; then
        echo "  ℹ Hospital PACS containers not yet running or not accessible"
        echo "  → Start the sandbox with scripts/04-run-sandbox.sh"
        echo "  → Then run: RELOAD_TESTDATA=true bash scripts/04-run-sandbox.sh $SANDBOX_PATH"
        echo "     to upload the test data to running containers"
    fi
    echo ""
fi

