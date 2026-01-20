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

echo "=========================================="
echo "Uploading Sample DICOM Data"
echo "=========================================="
echo ""

# Check if data directory exists
if [ ! -d "$DATA_DIR/study-001" ]; then
    echo "❌ Error: Sample data not found at $DATA_DIR/study-001"
    echo "Please ensure the data/sample-studies/study-001 directory exists."
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
total=$(find "$DATA_DIR/study-001" -name "*.dcm" -type f | wc -l)

for dcm_file in $(find "$DATA_DIR/study-001" -name "*.dcm" -type f); do
    result=$(curl -s -X POST -H "Content-Type: application/dicom" \
        --data-binary @"$dcm_file" \
        http://localhost:8063/instances 2>&1)
    
    if echo "$result" | grep -q "Success"; then
        uploaded=$((uploaded + 1))
    else
        failed=$((failed + 1))
    fi
done

echo "  ✓ Uploaded $uploaded/$total files to hospital-1-query"
if [ $failed -gt 0 ]; then
    echo "  ⚠ Failed to upload $failed files"
fi
echo ""

# Upload sample files to hospital-2
echo "Uploading sample files to hospital-2..."
uploaded=0
sample_files=("$WORKSPACE_ROOT/sandbox/PACS-AI/node_modules/dicomweb-client/testData"/*.dcm)

if [ ${#sample_files[@]} -gt 0 ] && [ -f "${sample_files[0]}" ]; then
    for dcm_file in "${sample_files[@]}"; do
        [ -f "$dcm_file" ] || continue
        
        result=$(curl -s -X POST -H "Content-Type: application/dicom" \
            --data-binary @"$dcm_file" \
            http://localhost:8083/instances 2>&1)
        
        if echo "$result" | grep -q "Success"; then
            uploaded=$((uploaded + 1))
        fi
    done
    echo "  ✓ Uploaded $uploaded sample files to hospital-2"
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
