#!/bin/bash

# ==========================================
# Upload Sample DICOM Data to Hospital Orthanc Instances
# ==========================================
# This script uploads sample DICOM studies to the hospital PACS simulators
# Run this after the containers are started and modalities are registered
# ==========================================

set -e

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$WORKSPACE_ROOT/data/sample-studies"

# Parse command line arguments
STUDY_PATH="${1:-study-001}"  # Default to study-001 if no argument provided

# If relative path, prepend DATA_DIR; if absolute, use as-is
if [[ "$STUDY_PATH" != /* ]]; then
    FULL_STUDY_PATH="$DATA_DIR/$STUDY_PATH"
else
    FULL_STUDY_PATH="$STUDY_PATH"
fi

echo "=========================================="
echo "Uploading Sample DICOM Data"
echo "=========================================="
echo ""
echo "Study directory: $FULL_STUDY_PATH"
echo ""

# Check if data directory exists
if [ ! -d "$FULL_STUDY_PATH" ]; then
    echo "❌ Error: Sample data not found at $FULL_STUDY_PATH"
    echo "Please ensure the directory exists."
    echo ""
    echo "Usage: $0 [study-directory]"
    echo "  study-directory: Path to study folder (relative to data/sample-studies/ or absolute)"
    echo "  Default: study-001"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Upload study-001 (default)"
    echo "  $0 gaobowen-longitudinal             # Upload specific study"
    echo "  $0 /path/to/custom/study             # Upload from absolute path"
    exit 1
fi

# Wait for Orthanc instances to be ready
wait_for_orthanc() {
    local name="$1"
    local port="$2"
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for $name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:$port/system 2>&1 | grep -q "Version"; then
            echo "  ✓ $name is ready"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echo "  ⚠ Warning: $name did not become ready in time"
    return 1
}

# Check all orthanc instances are running
echo "Checking Orthanc instances..."
wait_for_orthanc "hospital-1-query" 8063 || exit 1
wait_for_orthanc "hospital-2" 8083 || exit 1
echo ""

# Upload to hospital-1-query
echo "Uploading studies to hospital-1-query..."
uploaded=0
failed=0
total=$(find "$FULL_STUDY_PATH" -type f \( -name "*.dcm" -o -name "*.IMA" \) | wc -l)
echo "  Found $total DICOM files to upload..."

while IFS= read -r dcm_file; do
    result=$(curl -s -X POST -H "Content-Type: application/dicom" \
        --data-binary @"$dcm_file" \
        http://localhost:8063/instances 2>&1)
    
    # Check if the response contains an ID field (indicates success)
    if echo "$result" | grep -q '"ID"'; then
        uploaded=$((uploaded + 1))
        # Show progress every 10 files
        if [ $((uploaded % 10)) -eq 0 ]; then
            echo "  Progress: $uploaded/$total files uploaded..."
        fi
    else
        failed=$((failed + 1))
        echo "  ✗ Failed to upload: $(basename "$dcm_file")"
        echo "    Response: $result" | head -1
    fi
done < <(find "$FULL_STUDY_PATH" -type f \( -name "*.dcm" -o -name "*.IMA" \))

echo "  ✓ Uploaded $uploaded/$total files to hospital-1-query"
if [ $failed -gt 0 ]; then
    echo "  ⚠ Failed to upload $failed files"
fi
echo ""

# Upload sample files to hospital-2
echo "Uploading sample files to hospital-2..."
uploaded=0
failed=0
sample_files=("$WORKSPACE_ROOT/sandbox/PACS-AI/node_modules/dicomweb-client/testData"/*.dcm)

if [ ${#sample_files[@]} -gt 0 ] && [ -f "${sample_files[0]}" ]; then
    for dcm_file in "${sample_files[@]}"; do
        [ -f "$dcm_file" ] || continue
        
        result=$(curl -s -X POST -H "Content-Type: application/dicom" \
            --data-binary @"$dcm_file" \
            http://localhost:8083/instances 2>&1)
        
        # Check if the response contains an ID field (indicates success)
        if echo "$result" | grep -q '"ID"'; then
            uploaded=$((uploaded + 1))
        else
            failed=$((failed + 1))
            echo "  ✗ Failed to upload: $(basename "$dcm_file")"
        fi
    done
    echo "  ✓ Uploaded $uploaded sample files to hospital-2"
    if [ $failed -gt 0 ]; then
        echo "  ⚠ Failed to upload $failed sample files"
    fi
else
    echo "  ℹ No sample files found in node_modules (frontend not yet built)"
fi
echo ""

# Summary
echo "=========================================="
echo "Upload Complete!"
echo "=========================================="
echo ""
echo "Studies uploaded to hospital-1-query (localhost:8063):"
for study in $(curl -s http://localhost:8063/studies | jq -r '.[]'); do
    curl -s http://localhost:8063/studies/$study | jq -r '"  • " + .MainDicomTags.StudyDate + " - " + (.PatientMainDicomTags.PatientName // "Unknown") + " (" + (.MainDicomTags.StudyDescription // "No description") + ")"'
done
echo ""

echo "Studies uploaded to hospital-2 (localhost:8083):"
study_count=$(curl -s http://localhost:8083/studies | jq -r 'length')
if [ "$study_count" -gt 0 ]; then
    for study in $(curl -s http://localhost:8083/studies | jq -r '.[]'); do
        curl -s http://localhost:8083/studies/$study | jq -r '"  • " + .MainDicomTags.StudyDate + " - " + (.PatientMainDicomTags.PatientName // "Unknown") + " (" + (.MainDicomTags.StudyDescription // "No description") + ")"'
    done
else
    echo "  (No studies uploaded - sample files not available)"
fi
echo ""

echo "You can now query these studies through the PACS-AI frontend!"
echo "Remember to configure modalities via Admin UI (enable C-FIND/C-MOVE/C-STORE)."
echo ""
