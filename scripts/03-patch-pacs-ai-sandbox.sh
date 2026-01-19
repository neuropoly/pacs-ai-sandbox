#!/usr/bin/env bash

# Patch PACS-AI sandbox to fix Docker networking and configuration issues
# This script should be run after 02-create-sandbox.sh and before 04-run-sandbox.sh

SANDBOX_PATH=$1

set -e

if [ -z "$SANDBOX_PATH" ]; then
    echo "Error: SANDBOX_PATH argument is required"
    echo "Usage: bash scripts/03-patch-pacs-ai-sandbox.sh <sandbox-path>"
    exit 1
fi

if [ ! -d "$SANDBOX_PATH" ]; then
    echo "Error: Sandbox path does not exist: $SANDBOX_PATH"
    exit 1
fi

echo "=========================================="
echo "Patching PACS-AI Sandbox"
echo "=========================================="
echo ""

# 1. Fix redis.conf permissions
echo "1. Fixing redis.conf permissions..."
chmod 644 "$SANDBOX_PATH/pacs-ai-backend/redis/redis.conf"
echo "   ✓ redis.conf permissions set to 644"
echo ""

# 2. Patch redis docker-compose to add network
echo "2. Patching redis/docker-compose-dev.yml to add network..."
cat > "$SANDBOX_PATH/pacs-ai-backend/redis/docker-compose-dev.yml" << 'EOF'
services:
  redis:
    image: redis:8.0-M02-bookworm
    container_name: redis
    restart: always
    command: ["redis-server", "/etc/redis/redis.conf"]
    networks:
      - default
    volumes:
      - ./redis.conf:/etc/redis/redis.conf
    ports:
      - 6379:6379
EOF
echo "   ✓ Redis network configuration added"
echo ""

# 3. Patch nginx docker-compose to add network
echo "3. Patching nginx/docker-compose-dev.yml to add network..."
cat > "$SANDBOX_PATH/pacs-ai-backend/nginx/docker-compose-dev.yml" << 'EOF'
services:
  nginx:
    build:
      context: .
      dockerfile: Dockerfile-dev
    container_name: nginx
    restart: unless-stopped
    networks:
      - default
    ports:
      - 80:80
    depends_on:
      - orthanc
      - api-pacs
EOF
echo "   ✓ NGINX network configuration added"
echo ""

# 4. Enable orthanc-pacs in docker-compose
echo "4. Enabling orthanc-pacs (hospital PACS simulation containers)..."
if grep -q "^#.*orthanc-pacs" "$SANDBOX_PATH/pacs-ai-backend/docker-compose-dev.yml" 2>/dev/null; then
    sed -i 's/^#.*orthanc-pacs/  - orthanc-pacs\/docker-compose.yml/' "$SANDBOX_PATH/pacs-ai-backend/docker-compose-dev.yml"
    echo "   ✓ orthanc-pacs enabled"
elif grep -q "orthanc-pacs" "$SANDBOX_PATH/pacs-ai-backend/docker-compose-dev.yml" 2>/dev/null; then
    echo "   ℹ orthanc-pacs already enabled"
else
    echo "   ⚠ orthanc-pacs line not found"
fi
echo ""

# 5. Fix orthanc-hospital-1 shared volume (CRITICAL: prevents SQLite database locks)
echo "5. Fixing orthanc-hospital-1 shared volume issue..."
if [ -f "$SANDBOX_PATH/pacs-ai-backend/orthanc-pacs/docker-compose.yml" ]; then
    # Use awk for precise replacement in the correct service sections
    awk '
        /^  orthanc-hospital-1-query:/ { in_query=1; in_store=0; in_volumes=0 }
        /^  orthanc-hospital-1-store:/ { in_query=0; in_store=1; in_volumes=0 }
        /^  orthanc-hospital-2:/ { in_query=0; in_store=0; in_volumes=0 }
        /^volumes:/ { in_query=0; in_store=0; in_volumes=1 }
        
        # In query service, replace volume
        in_query && /- orthanc-storage-hospital-1:/ {
            sub(/orthanc-storage-hospital-1:/, "orthanc-storage-hospital-1-query:")
        }
        
        # In store service, replace volume
        in_store && /- orthanc-storage-hospital-1:/ {
            sub(/orthanc-storage-hospital-1:/, "orthanc-storage-hospital-1-store:")
        }
        
        # In volumes section, replace single entry with two
        in_volumes && /^  orthanc-storage-hospital-1:$/ {
            print "  orthanc-storage-hospital-1-query:"
            print "  orthanc-storage-hospital-1-store:"
            next
        }
        
        { print }
    ' "$SANDBOX_PATH/pacs-ai-backend/orthanc-pacs/docker-compose.yml" > "$SANDBOX_PATH/pacs-ai-backend/orthanc-pacs/docker-compose.yml.tmp"
    
    mv "$SANDBOX_PATH/pacs-ai-backend/orthanc-pacs/docker-compose.yml.tmp" "$SANDBOX_PATH/pacs-ai-backend/orthanc-pacs/docker-compose.yml"
    
    echo "   ✓ Separated volumes for orthanc-hospital-1-query and orthanc-hospital-1-store"
else
    echo "   ⚠ orthanc-pacs/docker-compose.yml not found"
fi
echo ""

# 6. Fix nginx routes to match actual container names
echo "6. Fixing nginx routes to match container names..."
if [ -f "$SANDBOX_PATH/pacs-ai-backend/nginx/default-dev.conf" ]; then
    # Change orthanc-hospital-1 to orthanc-hospital-1-query
    sed -i 's/location \/orthanc-hospital-1\//location \/orthanc-hospital-1-query\//' \
        "$SANDBOX_PATH/pacs-ai-backend/nginx/default-dev.conf"
    sed -i 's/proxy_pass http:\/\/orthanc-hospital-1:/proxy_pass http:\/\/orthanc-hospital-1-query:/' \
        "$SANDBOX_PATH/pacs-ai-backend/nginx/default-dev.conf"
    sed -i 's/rewrite \/orthanc-hospital-1(/rewrite \/orthanc-hospital-1-query(/' \
        "$SANDBOX_PATH/pacs-ai-backend/nginx/default-dev.conf"
    
    echo "   ✓ Updated nginx routes: orthanc-hospital-1 → orthanc-hospital-1-query"
else
    echo "   ⚠ nginx/default-dev.conf not found"
fi
echo ""

# 7. Register hospital DICOM modalities in main Orthanc
echo "7. Registering hospital DICOM modalities in main Orthanc..."
echo "   Note: This step requires orthanc container to be running"
echo "   Checking if orthanc container is running..."

# Only register modalities if orthanc is running
if docker ps --format '{{.Names}}' | grep -q '^orthanc$'; then
    echo "   Orthanc container is running, waiting for it to be ready..."
    
    # Wait for orthanc to be ready (max 30 seconds)
    max_attempts=30
    attempt=1
    orthanc_ready=false
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:8053/system 2>&1 | grep -q "Version"; then
            echo "   ✓ Orthanc is ready"
            orthanc_ready=true
            break
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    if [ "$orthanc_ready" = true ]; then
        echo "   Registering hospital-1-query modality..."
        curl -s -X PUT -H "Content-Type: application/json" \
            -d '["HOSPITAL_1_QUERY", "orthanc-hospital-1-query", 5000]' \
            http://localhost:8053/modalities/hospital-1-query > /dev/null
        
        echo "   Registering hospital-1-store modality..."
        curl -s -X PUT -H "Content-Type: application/json" \
            -d '["HOSPITAL_1_STORE", "orthanc-hospital-1-store", 4000]' \
            http://localhost:8053/modalities/hospital-1-store > /dev/null
        
        echo "   Registering hospital-2 modality..."
        curl -s -X PUT -H "Content-Type: application/json" \
            -d '["HOSPITAL_2", "orthanc-hospital-2", 4242]' \
            http://localhost:8053/modalities/hospital-2 > /dev/null
        
        # Verify registration
        modalities_json=$(curl -s http://localhost:8053/modalities)
        if echo "$modalities_json" | grep -q "hospital-1-query" && \
           echo "$modalities_json" | grep -q "hospital-1-store" && \
           echo "$modalities_json" | grep -q "hospital-2"; then
            echo "   ✓ All hospital DICOM modalities registered successfully"
        else
            echo "   ⚠ Warning: Some modalities may not have been registered"
        fi
    else
        echo "   ⚠ Orthanc did not become ready in time"
        echo "   ℹ Run this script again after containers are fully started"
    fi
else
    echo "   ⚠ Orthanc container is not running"
    echo "   ℹ Run this script again after running: bash scripts/04-run-sandbox.sh $SANDBOX_PATH"
fi
echo ""

echo "=========================================="
echo "Sandbox Patching Complete!"
echo "=========================================="
echo ""
echo "Changes applied:"
echo "  ✓ redis.conf permissions fixed (644)"
echo "  ✓ redis network configuration added"
echo "  ✓ nginx network configuration added"
echo "  ✓ orthanc-pacs enabled (hospital PACS simulation)"
echo "  ✓ orthanc-hospital-1 volume separation fixed (prevents SQLite locks)"
echo "  ✓ nginx routes updated to match actual container names"
echo "  ✓ Hospital DICOM modalities registered in Orthanc (if running)"
echo ""
echo "Hospital PACS Simulation Containers:"
echo "  • orthanc-hospital-1-query (DICOM Query/Move) - http://localhost:8063"
echo "  • orthanc-hospital-1-store (DICOM Store)      - http://localhost:8073"
echo "  • orthanc-hospital-2 (Combined)               - http://localhost:8083"
echo "  • Main PACS-AI Orthanc                        - http://localhost:8053"
echo ""
echo "Registered DICOM Modalities:"
echo "  • hospital-1-query (HOSPITAL_1_QUERY @ orthanc-hospital-1-query:5000)"
echo "  • hospital-1-store (HOSPITAL_1_STORE @ orthanc-hospital-1-store:4000)"
echo "  • hospital-2       (HOSPITAL_2 @ orthanc-hospital-2:4242)"
echo ""
echo "Nginx Routes:"
echo "  • http://localhost/orthanc-hospital-1-query/"
echo "  • http://localhost/orthanc-hospital-2/"
echo "  • http://localhost/api/"
echo ""
echo "Next steps:"
echo "  1. Run: bash scripts/04-run-sandbox.sh $SANDBOX_PATH"
echo "  2. Access frontend at http://localhost:3000"
echo "  3. Create tenant owner account (see README for curl command)"
echo "  4. Configure modalities via Admin UI (enable C-FIND/C-MOVE/C-STORE)"
echo "     See 'Post-Deployment Configuration' section in README.md"
echo ""
echo "Note: Hospital DICOM modalities are registered in Orthanc but C-FIND/C-MOVE/C-STORE"
echo "      flags default to disabled. Enable them via Admin UI after first login."
echo ""
