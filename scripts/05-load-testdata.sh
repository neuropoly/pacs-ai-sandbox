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
# Testdata could be in several locations since it may be a submodule
POSSIBLE_PATHS=(
    "$REPO_ROOT/external/pacs-ai-frontend/platform/app/public/testdata"
    "$REPO_ROOT/external/pacs-ai-frontend/testdata"
    "$REPO_ROOT/external/pacs-ai-frontend/platform/testdata"
    "$REPO_ROOT/external/pacs-ai-frontend/extensions/default/testdata"
)

FRONTEND_TESTDATA=""

echo "   Searching for testdata in pacs-ai-frontend..."
for path in "${POSSIBLE_PATHS[@]}"; do
    echo "   Checking: ${path#$REPO_ROOT/}"
    if [ -d "$path" ]; then
        FRONTEND_TESTDATA="$path"
        echo "   ✓ Found testdata at: ${path#$REPO_ROOT/}"
        break
    fi
done

if [ -z "$FRONTEND_TESTDATA" ]; then
    echo "   ⚠ No testdata directory found in standard locations"
    echo "   ℹ Submodules may not be initialized. Run:"
    echo "     git -C external/pacs-ai-frontend submodule update --init --recursive"
    echo "   Skipping testdata loading"
fi

if [ -n "$FRONTEND_TESTDATA" ] && [ -d "$FRONTEND_TESTDATA" ]; then
    echo "   ✓ Found testdata at: $FRONTEND_TESTDATA"
    
    # Create testdata directory in local data folder
    mkdir -p "$REPO_ROOT/data/sample-studies/testdata-from-external"
    
    # Check what's in the testdata directory
    # Look for DICOM files (.dcm)
    DICOM_FILES=$(find "$FRONTEND_TESTDATA" -name "*.dcm" 2>/dev/null | wc -l)
    
    # Look for DICOMweb data (JSON metadata files, common in DICOMweb)
    DICOMWEB_JSON=$(find "$FRONTEND_TESTDATA" -name "*.json" 2>/dev/null | wc -l)
    
    # Check if there are any subdirectories (testdata structure)
    SUBDIRS=$(find "$FRONTEND_TESTDATA" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    
    # Count total files to see if directory has any content
    TOTAL_FILES=$(find "$FRONTEND_TESTDATA" -type f 2>/dev/null | wc -l)
    
    echo "   ℹ Found $DICOM_FILES DICOM (.dcm) files"
    echo "   ℹ Found $DICOMWEB_JSON JSON metadata files"
    echo "   ℹ Found $SUBDIRS subdirectories"
    echo "   ℹ Total files: $TOTAL_FILES"
    
    # If there's any content in testdata, process it
    if [ "$TOTAL_FILES" -gt 0 ]; then
        echo "   → Processing testdata content..."
        
        # Copy DICOM files if found
        if [ "$DICOM_FILES" -gt 0 ]; then
            echo "   → Copying DICOM files..."
            find "$FRONTEND_TESTDATA" -name "*.dcm" -exec cp {} "$REPO_ROOT/data/sample-studies/testdata-from-external/" \; 2>/dev/null || true
            echo "   ✓ Copied DICOM files to data/sample-studies/testdata-from-external/"
        fi
        
        # Copy ALL testdata to frontend (DICOMweb data, JSON, images, etc.)
        SANDBOX_FRONTEND="$SANDBOX_PATH/PACS-AI/platform/app/public"
        
        if [ -d "$SANDBOX_FRONTEND" ]; then
            # Ensure testdata directory exists in sandbox
            mkdir -p "$SANDBOX_FRONTEND/testdata"
            
            # Copy all testdata content (this includes DICOMweb studies, JSON files, images, etc.)
            echo "   → Copying all testdata to sandbox frontend..."
            cp -R "$FRONTEND_TESTDATA"/. "$SANDBOX_FRONTEND/testdata/" 2>/dev/null || true
            
            # Verify the copy
            COPIED_FILES=$(find "$SANDBOX_FRONTEND/testdata" -type f 2>/dev/null | wc -l)
            if [ "$COPIED_FILES" -gt 0 ]; then
                echo "   ✓ Copied $COPIED_FILES files to sandbox/PACS-AI/platform/app/public/testdata/"
                echo "   ✓ DICOMweb data will be served by frontend application"
            else
                echo "   ⚠ No files were copied - check permissions or paths"
            fi
        else
            echo "   ⚠ Sandbox frontend public directory not found at: $SANDBOX_FRONTEND"
        fi
    else
        echo "   ℹ Testdata directory exists but appears to be empty"
        echo "   ℹ This may be normal if submodules haven't been initialized"
        echo "   ℹ Run: git -C external/pacs-ai-frontend submodule update --init --recursive"
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
    
    # Function to upload DICOM files to an Orthanc instance
    upload_to_orthanc() {
        local orthanc_url=$1
        local orthanc_name=$2
        local upload_count=0
        
        if curl -s -f "$orthanc_url/system" > /dev/null 2>&1; then
            echo "  → Uploading to $orthanc_name ($orthanc_url)..."
            for dcm_file in "$REPO_ROOT/data/sample-studies/testdata-from-external"/*.dcm; do
                if [ -f "$dcm_file" ]; then
                    if curl -s -X POST "$orthanc_url/instances" \
                        -H "Content-Type: application/dicom" \
                        --data-binary "@$dcm_file" > /dev/null 2>&1; then
                        ((upload_count++))
                    fi
                fi
            done
            if [ "$upload_count" -gt 0 ]; then
                echo "    ✓ Uploaded $upload_count DICOM files to $orthanc_name"
                return 0
            fi
        fi
        return 1
    }
    
    # Check if we can reach the hospital PACS containers
    # These are typically at localhost:8063, 8073, 8083 when running
    
    UPLOADED=false
    
    # Try uploading to hospital PACS containers
    if command -v curl &> /dev/null; then
        upload_to_orthanc "http://localhost:8073" "orthanc-hospital-1-store" && UPLOADED=true
        upload_to_orthanc "http://localhost:8083" "orthanc-hospital-2" && UPLOADED=true
    fi
    
    if [ "$UPLOADED" = false ]; then
        echo "  ℹ Hospital PACS containers not yet running or not accessible"
        echo "  → Start the sandbox with scripts/04-run-sandbox.sh"
        echo "  → Then run: RELOAD_TESTDATA=true bash scripts/04-run-sandbox.sh $SANDBOX_PATH"
        echo "     to upload the test data to running containers"
    fi
    echo ""
fi

