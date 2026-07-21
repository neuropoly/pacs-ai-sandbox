#!/bin/bash

# ==========================================
# Clean DICOM Data from Orthanc Instances
# ==========================================
# This script allows selective deletion of DICOM studies and series from
# Orthanc instances based on various criteria (date, patient, modality, etc.)
# ==========================================

set -e

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default values
DATE_FROM=""
DATE_TO=""
UPLOADED_FROM=""
UPLOADED_TO=""
PATIENT_FILTER=""
STUDY_FILTER=""
MODALITY_FILTER=""
INSTANCE="all"
SKIP_CONFIRMATION=false

# Orthanc instance configurations
declare -A ORTHANC_PORTS=(
    ["hospital-1"]="8063"
    ["hospital-2"]="8083"
)

declare -A ORTHANC_NAMES=(
    ["hospital-1"]="hospital-1-query"
    ["hospital-2"]="hospital-2"
)

# Arrays to track what needs deletion
declare -a STUDIES_TO_DELETE
declare -a SERIES_TO_DELETE
declare -a STUDIES_WITH_PARTIAL_DELETE

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==========================================
# Helper Functions
# ==========================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean DICOM data from Orthanc instances based on filters.

OPTIONS:
    --date-from DATE           Filter series with SeriesDate >= this date
    --date-to DATE             Filter series with SeriesDate <= this date
    --uploaded-from TIMESTAMP  Filter series uploaded on/after this date
    --uploaded-to TIMESTAMP    Filter series uploaded on/before this date
    --patient NAME             Filter by patient name (partial, case-insensitive)
    --study DESC               Filter by study description (partial, case-insensitive)
    --modality MODALITY        Filter by modality (e.g., CT, MR, PT)
    --instance NAME            Target instance: hospital-1, hospital-2, or all (default: all)
    --yes                      Skip confirmation prompt
    -h, --help                 Show this help message

DATE/TIMESTAMP FORMATS:
    All date arguments support both exact dates and human-readable expressions:
    
    Exact formats:
        YYYYMMDD           e.g., 20240615
        YYYYMMDDTHHMMSS    e.g., 20240615T143000
    
    Human-readable (uses GNU date):
        today, yesterday, tomorrow
        "N days ago", "N weeks ago", "N months ago"
        "N hours ago", "N minutes ago"
        "last Monday", "last week", "last month"
        
    Examples:
        --uploaded-from today
        --uploaded-to yesterday
        --date-from "2 weeks ago"
        --uploaded-from "1 hour ago"
        --date-to "last Monday"

EXAMPLES:
    # Delete all CT series from June 2024
    $0 --date-from 20240601 --date-to 20240630 --modality CT

    # Delete data uploaded today (human-readable)
    $0 --uploaded-from today

    # Delete data uploaded in the last hour
    $0 --uploaded-from "1 hour ago"

    # Delete data uploaded before yesterday
    $0 --uploaded-to yesterday

    # Delete MR series from last week
    $0 --modality MR --date-from "last week"

    # Delete all data for a specific patient
    $0 --patient "John Doe"

    # Delete everything from hospital-1 (with confirmation)
    $0 --instance hospital-1

    # Delete all data from all instances (DANGER!)
    $0 --yes

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --date-from)
                DATE_FROM=$(parse_human_date "$2" "date")
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Error: Invalid date format for --date-from: $2${NC}"
                    exit 1
                fi
                shift 2
                ;;
            --date-to)
                DATE_TO=$(parse_human_date "$2" "date")
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Error: Invalid date format for --date-to: $2${NC}"
                    exit 1
                fi
                shift 2
                ;;
            --uploaded-from)
                UPLOADED_FROM=$(parse_human_date "$2" "timestamp")
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Error: Invalid date format for --uploaded-from: $2${NC}"
                    exit 1
                fi
                shift 2
                ;;
            --uploaded-to)
                UPLOADED_TO=$(parse_human_date "$2" "timestamp")
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}Error: Invalid date format for --uploaded-to: $2${NC}"
                    exit 1
                fi
                shift 2
                ;;
            --patient)
                PATIENT_FILTER="$2"
                shift 2
                ;;
            --study)
                STUDY_FILTER="$2"
                shift 2
                ;;
            --modality)
                MODALITY_FILTER="$2"
                shift 2
                ;;
            --instance)
                INSTANCE="$2"
                shift 2
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check if Orthanc instance is available
check_orthanc() {
    local port="$1"
    if ! curl -s http://localhost:$port/system >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Case-insensitive string matching
matches_string() {
    local value="$1"
    local filter="$2"
    
    if [[ -z "$filter" ]]; then
        return 0  # No filter means match all
    fi
    
    # Convert both to lowercase for case-insensitive comparison
    local value_lower=$(echo "$value" | tr '[:upper:]' '[:lower:]')
    local filter_lower=$(echo "$filter" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$value_lower" == *"$filter_lower"* ]]; then
        return 0
    fi
    return 1
}

# Parse human-readable date/timestamp into YYYYMMDD or YYYYMMDDTHHMMSS format
# Uses GNU date for natural language parsing
parse_human_date() {
    local input="$1"
    local output_type="$2"  # "date" for YYYYMMDD, "timestamp" for YYYYMMDDTHHMMSS
    
    # If empty, return empty
    if [[ -z "$input" ]]; then
        echo ""
        return 0
    fi
    
    # Check if already in correct format (YYYYMMDD or YYYYMMDDTHHMMSS)
    if [[ "$input" =~ ^[0-9]{8}$ ]] || [[ "$input" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        echo "$input"
        return 0
    fi
    
    # Try to parse using GNU date
    # For human-readable dates, always output date-only format (YYYYMMDD)
    # This allows the existing normalization logic to handle start/end of day correctly
    local parsed=""
    parsed=$(date -d "$input" +%Y%m%d 2>/dev/null)
    
    if [[ $? -ne 0 || -z "$parsed" ]]; then
        echo "Error: Unable to parse date '$input'." >&2
        echo "Supported formats: YYYYMMDD, YYYYMMDDTHHMMSS, or human-readable (e.g., 'today', '2 days ago')" >&2
        return 1
    fi
    
    echo "$parsed"
    return 0
}

# Check if date is within range
date_in_range() {
    local date="$1"
    local from="$2"
    local to="$3"
    
    # If no date filters, match all
    if [[ -z "$from" && -z "$to" ]]; then
        return 0
    fi
    
    # Check from date
    if [[ -n "$from" && "$date" < "$from" ]]; then
        return 1
    fi
    
    # Check to date
    if [[ -n "$to" && "$date" > "$to" ]]; then
        return 1
    fi
    
    return 0
}

# Normalize timestamp for comparison (handles both YYYYMMDD and YYYYMMDDTHHMMSS)
# For date-only format, appends T000000 for "from" comparison and T235959 for "to" comparison
normalize_timestamp() {
    local timestamp="$1"
    local comparison_type="$2"  # "from" or "to"
    
    # If already full timestamp format, return as-is
    if [[ "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        echo "$timestamp"
        return
    fi
    
    # If date-only format (YYYYMMDD)
    if [[ "$timestamp" =~ ^[0-9]{8}$ ]]; then
        if [[ "$comparison_type" == "from" ]]; then
            # For lower bound: start of day (00:00:00)
            echo "${timestamp}T000000"
        else
            # For upper bound: end of day (23:59:59)
            echo "${timestamp}T235959"
        fi
        return
    fi
    
    # Invalid format, return as-is and let comparison fail naturally
    echo "$timestamp"
}

# Check if upload timestamp is within range
# Handles partial timestamps (YYYYMMDD) by normalizing them appropriately
upload_timestamp_in_range() {
    local timestamp="$1"
    local from="$2"
    local to="$3"
    
    # If no upload filters, match all
    if [[ -z "$from" && -z "$to" ]]; then
        return 0
    fi
    
    # Normalize bounds for comparison
    local normalized_from="$from"
    local normalized_to="$to"
    
    # Normalize "from" bound (use start of day if date-only)
    if [[ -n "$from" ]]; then
        normalized_from=$(normalize_timestamp "$from" "from")
        # Check lower bound: timestamp must be >= from
        if [[ "$timestamp" < "$normalized_from" ]]; then
            return 1
        fi
    fi
    
    # Normalize "to" bound (use end of day if date-only)
    if [[ -n "$to" ]]; then
        normalized_to=$(normalize_timestamp "$to" "to")
        # Check upper bound: timestamp must be <= to
        if [[ "$timestamp" > "$normalized_to" ]]; then
            return 1
        fi
    fi
    
    return 0
}

# Fetch all studies from an Orthanc instance
fetch_studies() {
    local port="$1"
    local studies=$(curl -s http://localhost:$port/studies 2>/dev/null)
    echo "$studies"
}

# Fetch study details
fetch_study_details() {
    local port="$1"
    local study_id="$2"
    local details=$(curl -s http://localhost:$port/studies/$study_id 2>/dev/null)
    echo "$details"
}

# Fetch series details
fetch_series_details() {
    local port="$1"
    local series_id="$2"
    local details=$(curl -s http://localhost:$port/series/$series_id 2>/dev/null)
    echo "$details"
}

# Delete a study
delete_study() {
    local port="$1"
    local study_id="$2"
    curl -s -X DELETE http://localhost:$port/studies/$study_id >/dev/null 2>&1
    return $?
}

# Delete a series
delete_series() {
    local port="$1"
    local series_id="$2"
    curl -s -X DELETE http://localhost:$port/series/$series_id >/dev/null 2>&1
    return $?
}

# Check if a study still exists (for cleanup)
study_exists() {
    local port="$1"
    local study_id="$2"
    local result=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port/studies/$study_id 2>/dev/null)
    if [[ "$result" == "200" ]]; then
        return 0
    fi
    return 1
}

# ==========================================
# Main Logic Functions
# ==========================================

# Process studies and build deletion lists
process_studies() {
    local instance_name="$1"
    local port="$2"
    
    echo -e "${BLUE}Analyzing ${ORTHANC_NAMES[$instance_name]} (localhost:$port)...${NC}"
    
    local studies=$(fetch_studies "$port")
    local study_count=$(echo "$studies" | jq -r 'length' 2>/dev/null)
    
    if [[ "$study_count" == "0" || "$study_count" == "null" ]]; then
        echo "  No studies found"
        return
    fi
    
    echo "  Found $study_count studies to analyze..."
    
    # Process each study
    for study_id in $(echo "$studies" | jq -r '.[]' 2>/dev/null); do
        local study_details=$(fetch_study_details "$port" "$study_id")
        
        # Extract study-level info
        local patient_name=$(echo "$study_details" | jq -r '.PatientMainDicomTags.PatientName // "Unknown"')
        local study_desc=$(echo "$study_details" | jq -r '.MainDicomTags.StudyDescription // ""')
        local study_date=$(echo "$study_details" | jq -r '.MainDicomTags.StudyDate // ""')
        
        # Apply study-level filters
        if ! matches_string "$patient_name" "$PATIENT_FILTER"; then
            continue
        fi
        
        if ! matches_string "$study_desc" "$STUDY_FILTER"; then
            continue
        fi
        
        # Get all series for this study
        local series_list=$(echo "$study_details" | jq -r '.Series[]' 2>/dev/null)
        local series_array=($series_list)
        local total_series=${#series_array[@]}
        local matching_series=0
        
        # Check each series against series-level filters
        for series_id in $series_list; do
            local series_details=$(fetch_series_details "$port" "$series_id")
            
            local series_date=$(echo "$series_details" | jq -r '.MainDicomTags.SeriesDate // ""')
            local modality=$(echo "$series_details" | jq -r '.MainDicomTags.Modality // ""')
            local series_desc=$(echo "$series_details" | jq -r '.MainDicomTags.SeriesDescription // ""')
            local last_update=$(echo "$series_details" | jq -r '.LastUpdate // ""')
            
            # Use study date as fallback if series date is missing
            if [[ -z "$series_date" ]]; then
                series_date="$study_date"
            fi
            
            # Apply series-level filters
            local series_matches=true
            
            if [[ -n "$MODALITY_FILTER" && "$modality" != "$MODALITY_FILTER" ]]; then
                series_matches=false
            fi
            
            if ! date_in_range "$series_date" "$DATE_FROM" "$DATE_TO"; then
                series_matches=false
            fi
            
            if ! upload_timestamp_in_range "$last_update" "$UPLOADED_FROM" "$UPLOADED_TO"; then
                series_matches=false
            fi
            
            if $series_matches; then
                matching_series=$((matching_series + 1))
                SERIES_TO_DELETE+=("$port|$study_id|$series_id|$patient_name|$study_desc|$series_desc|$modality|$series_date")
            fi
        done
        
        # Determine deletion strategy for this study
        if [[ $matching_series -gt 0 ]]; then
            if [[ $matching_series -eq $total_series ]]; then
                # All series match - delete entire study (more efficient)
                STUDIES_TO_DELETE+=("$port|$study_id|$patient_name|$study_desc|$study_date|$total_series")
                # Remove individual series entries for this study
                if [[ ${#SERIES_TO_DELETE[@]} -gt 0 ]]; then
                    SERIES_TO_DELETE=($(printf '%s\n' "${SERIES_TO_DELETE[@]}" | grep -v "^$port|$study_id|" || true))
                fi
            else
                # Partial match - track for cleanup later
                STUDIES_WITH_PARTIAL_DELETE+=("$port|$study_id")
            fi
        fi
    done
}

# Display preview of what will be deleted
show_preview() {
    echo ""
    echo "=========================================="
    echo "DELETION PREVIEW"
    echo "=========================================="
    echo ""
    
    local total_studies=${#STUDIES_TO_DELETE[@]}
    local total_series=${#SERIES_TO_DELETE[@]}
    
    if [[ $total_studies -eq 0 && $total_series -eq 0 ]]; then
        echo -e "${GREEN}No items match the specified filters.${NC}"
        echo "Nothing to delete."
        return 1
    fi
    
    # Show studies that will be fully deleted
    if [[ $total_studies -gt 0 ]]; then
        echo -e "${RED}Studies to be FULLY deleted ($total_studies):${NC}"
        echo ""
        for entry in "${STUDIES_TO_DELETE[@]}"; do
            IFS='|' read -r port study_id patient_name study_desc study_date series_count <<< "$entry"
            local instance_name=""
            for key in "${!ORTHANC_PORTS[@]}"; do
                if [[ "${ORTHANC_PORTS[$key]}" == "$port" ]]; then
                    instance_name="${ORTHANC_NAMES[$key]}"
                    break
                fi
            done
            echo -e "  ${YELLOW}[$instance_name]${NC} $study_date - $patient_name"
            echo "    Study: $study_desc"
            echo "    Series count: $series_count"
            echo ""
        done
    fi
    
    # Show individual series that will be deleted
    if [[ $total_series -gt 0 ]]; then
        echo -e "${RED}Individual series to be deleted ($total_series):${NC}"
        echo ""
        local current_study=""
        for entry in "${SERIES_TO_DELETE[@]}"; do
            IFS='|' read -r port study_id series_id patient_name study_desc series_desc modality series_date <<< "$entry"
            
            # Print study header if new study
            if [[ "$current_study" != "$port|$study_id" ]]; then
                current_study="$port|$study_id"
                local instance_name=""
                for key in "${!ORTHANC_PORTS[@]}"; do
                    if [[ "${ORTHANC_PORTS[$key]}" == "$port" ]]; then
                        instance_name="${ORTHANC_NAMES[$key]}"
                        break
                    fi
                done
                echo -e "  ${YELLOW}[$instance_name]${NC} $patient_name - $study_desc"
            fi
            
            echo "    ↳ $series_date [$modality] - $series_desc"
        done
        echo ""
    fi
    
    echo ""
    echo -e "${RED}TOTAL: $total_studies complete studies + $total_series individual series will be deleted${NC}"
    
    return 0
}

# Perform the actual deletions
perform_deletions() {
    echo ""
    echo "=========================================="
    echo "PERFORMING DELETIONS"
    echo "=========================================="
    echo ""
    
    local deleted_studies=0
    local deleted_series=0
    local failed=0
    
    # Delete complete studies first
    if [[ ${#STUDIES_TO_DELETE[@]} -gt 0 ]]; then
        echo "Deleting complete studies..."
        for entry in "${STUDIES_TO_DELETE[@]}"; do
            IFS='|' read -r port study_id patient_name study_desc study_date series_count <<< "$entry"
            
            if delete_study "$port" "$study_id"; then
                deleted_studies=$((deleted_studies + 1))
                echo "  ✓ Deleted study: $patient_name - $study_desc"
            else
                failed=$((failed + 1))
                echo "  ✗ Failed to delete study: $patient_name - $study_desc"
            fi
        done
        echo ""
    fi
    
    # Delete individual series
    if [[ ${#SERIES_TO_DELETE[@]} -gt 0 ]]; then
        echo "Deleting individual series..."
        for entry in "${SERIES_TO_DELETE[@]}"; do
            IFS='|' read -r port study_id series_id patient_name study_desc series_desc modality series_date <<< "$entry"
            
            if delete_series "$port" "$series_id"; then
                deleted_series=$((deleted_series + 1))
                echo "  ✓ Deleted series: [$modality] $series_desc"
            else
                failed=$((failed + 1))
                echo "  ✗ Failed to delete series: [$modality] $series_desc"
            fi
        done
        echo ""
    fi
    
    # Cleanup empty studies
    if [[ ${#STUDIES_WITH_PARTIAL_DELETE[@]} -gt 0 ]]; then
        echo "Cleaning up empty studies..."
        for entry in "${STUDIES_WITH_PARTIAL_DELETE[@]}"; do
            IFS='|' read -r port study_id <<< "$entry"
            
            # Check if study still has series
            local study_details=$(fetch_study_details "$port" "$study_id")
            local remaining_series=$(echo "$study_details" | jq -r '.Series | length' 2>/dev/null)
            
            if [[ "$remaining_series" == "0" ]]; then
                if delete_study "$port" "$study_id"; then
                    deleted_studies=$((deleted_studies + 1))
                    echo "  ✓ Cleaned up empty study"
                fi
            fi
        done
        echo ""
    fi
    
    # Summary
    echo "=========================================="
    echo "DELETION SUMMARY"
    echo "=========================================="
    echo ""
    echo -e "${GREEN}Successfully deleted:${NC}"
    echo "  • $deleted_studies studies"
    echo "  • $deleted_series series"
    
    if [[ $failed -gt 0 ]]; then
        echo ""
        echo -e "${RED}Failed deletions: $failed${NC}"
    fi
    echo ""
}

# ==========================================
# Main Script
# ==========================================

main() {
    parse_arguments "$@"
    
    echo "=========================================="
    echo "Orthanc Data Cleanup Tool"
    echo "=========================================="
    echo ""
    
    # Show active filters
    echo "Active filters:"
    [[ -n "$DATE_FROM" ]] && echo "  • Series date from: $DATE_FROM"
    [[ -n "$DATE_TO" ]] && echo "  • Series date to: $DATE_TO"
    [[ -n "$UPLOADED_FROM" ]] && echo "  • Uploaded from: $UPLOADED_FROM"
    [[ -n "$UPLOADED_TO" ]] && echo "  • Uploaded to: $UPLOADED_TO"
    [[ -n "$PATIENT_FILTER" ]] && echo "  • Patient: $PATIENT_FILTER"
    [[ -n "$STUDY_FILTER" ]] && echo "  • Study: $STUDY_FILTER"
    [[ -n "$MODALITY_FILTER" ]] && echo "  • Modality: $MODALITY_FILTER"
    echo "  • Instance: $INSTANCE"
    
    if [[ -z "$DATE_FROM" && -z "$DATE_TO" && -z "$UPLOADED_FROM" && -z "$UPLOADED_TO" && -z "$PATIENT_FILTER" && -z "$STUDY_FILTER" && -z "$MODALITY_FILTER" ]]; then
        echo ""
        echo -e "${YELLOW}WARNING: No filters specified - this will affect ALL data!${NC}"
    fi
    echo ""
    
    # Determine which instances to process
    declare -a instances_to_process
    if [[ "$INSTANCE" == "all" ]]; then
        instances_to_process=("hospital-1" "hospital-2")
    else
        instances_to_process=("$INSTANCE")
    fi
    
    # Check instances are available
    for inst in "${instances_to_process[@]}"; do
        local port="${ORTHANC_PORTS[$inst]}"
        if [[ -z "$port" ]]; then
            echo -e "${RED}Error: Unknown instance '$inst'${NC}"
            echo "Valid instances: hospital-1, hospital-2, all"
            exit 1
        fi
        
        if ! check_orthanc "$port"; then
            echo -e "${RED}Error: ${ORTHANC_NAMES[$inst]} is not available at localhost:$port${NC}"
            exit 1
        fi
    done
    
    # Process each instance
    for inst in "${instances_to_process[@]}"; do
        process_studies "$inst" "${ORTHANC_PORTS[$inst]}"
    done
    
    # Show preview
    if ! show_preview; then
        exit 0
    fi
    
    # Confirmation
    if ! $SKIP_CONFIRMATION; then
        echo ""
        echo -e "${YELLOW}Are you sure you want to proceed with these deletions?${NC}"
        read -p "Type 'yes' to confirm: " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            echo ""
            echo "Operation cancelled."
            exit 0
        fi
    fi
    
    # Execute deletions
    perform_deletions
    
    echo "Done!"
}

# Run main function
main "$@"
