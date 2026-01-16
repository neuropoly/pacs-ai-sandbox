#!/usr/bin/env bash

# PACS-AI Network Connectivity Test Script
# Tests all services to ensure they're alive, accessible, and properly configured

set -e

echo "================================================"
echo "PACS-AI Network Connectivity Test"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASS=0
FAIL=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((FAIL++))
    fi
}

echo "1. DOCKER CONTAINER STATUS"
echo "-------------------------------------------"
echo "Checking running containers..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "nginx|api-pacs|redis|elasticsearch|orthanc"
echo ""

echo "2. DOCKER NETWORK CONNECTIVITY"
echo "-------------------------------------------"

# Check if pacs-net-default network exists
docker network inspect pacs-net-default &>/dev/null
test_result $? "Docker network 'pacs-net-default' exists"

# Check if pacs-net network exists
docker network inspect pacs-net &>/dev/null
test_result $? "Docker network 'pacs-net' exists"

echo ""
echo "3. CONTAINER HEALTH CHECKS"
echo "-------------------------------------------"

# Redis
docker exec redis redis-cli -a pacs.staging ping &>/dev/null
test_result $? "Redis: Responding to ping (with authentication)"

# Elasticsearch
curl -s http://localhost:9200/_cluster/health &>/dev/null
test_result $? "Elasticsearch: HTTP responding on localhost:9200"

# Orthanc
curl -s http://localhost:8053/system &>/dev/null
test_result $? "Orthanc: HTTP responding on localhost:8053"

echo ""
echo "4. INTERNAL CONTAINER COMMUNICATION"
echo "-------------------------------------------"

# Test if api-pacs can resolve 'redis' hostname
docker run --rm --network pacs-net-default alpine sh -c "ping -c 1 redis" &>/dev/null
test_result $? "DNS: 'redis' hostname resolves in pacs-net-default network"

# Test if api-pacs container exists and can be pinged
if docker ps | grep -q "api-pacs"; then
    docker run --rm --network pacs-net-default alpine sh -c "ping -c 1 api-pacs" &>/dev/null
    test_result $? "DNS: 'api-pacs' hostname resolves in pacs-net-default network"
else
    echo -e "${RED}✗ FAIL${NC}: api-pacs container is not running"
    ((FAIL++))
fi

# Test if nginx container can reach api-pacs
if docker ps | grep -q "nginx"; then
    docker run --rm --network pacs-net-default alpine sh -c "ping -c 1 nginx" &>/dev/null
    test_result $? "DNS: 'nginx' hostname resolves in pacs-net-default network"
else
    echo -e "${RED}✗ FAIL${NC}: nginx container is not running"
    ((FAIL++))
fi

echo ""
echo "5. HOST TO CONTAINER CONNECTIVITY"
echo "-------------------------------------------"

# Test port 80 (nginx)
curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -E "200|301|302|404" &>/dev/null
test_result $? "NGINX: Port 80 accessible from host"

# Test port 3000 (PACS-AI frontend)
curl -s http://localhost:3000 | grep -q "OHIF" &>/dev/null
test_result $? "Frontend: PACS-AI serving on port 3000"

# Test port 6379 (Redis)
timeout 2 bash -c "</dev/tcp/localhost/6379" &>/dev/null
test_result $? "Redis: Port 6379 accessible from host"

# Test port 9200 (Elasticsearch)
timeout 2 bash -c "</dev/tcp/localhost/9200" &>/dev/null
test_result $? "Elasticsearch: Port 9200 accessible from host"

echo ""
echo "6. API ENDPOINT TESTS"
echo "-------------------------------------------"

# Test NGINX proxy to API
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/ 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    test_result 0 "API Gateway: /api/ endpoint reachable (HTTP $HTTP_CODE)"
else
    test_result 1 "API Gateway: /api/ endpoint NOT reachable (HTTP $HTTP_CODE)"
fi

# Test NGINX proxy to Orthanc
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/orthanc/system 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
    test_result 0 "Orthanc Proxy: /orthanc/ endpoint reachable (HTTP $HTTP_CODE)"
else
    test_result 1 "Orthanc Proxy: /orthanc/ endpoint NOT reachable (HTTP $HTTP_CODE)"
fi

echo ""
echo "7. CONFIGURATION VERIFICATION"
echo "-------------------------------------------"

# Check api-pacs .env configuration
if [ -f "sandbox/pacs-ai-backend/api-pacs/.env" ]; then
    REDIS_HOST=$(grep "^REDIS_HOST=" sandbox/pacs-ai-backend/api-pacs/.env | cut -d'=' -f2)
    if [ "$REDIS_HOST" = "redis" ]; then
        test_result 0 "Config: api-pacs REDIS_HOST set to 'redis' (correct for Docker)"
    else
        test_result 1 "Config: api-pacs REDIS_HOST set to '$REDIS_HOST' (should be 'redis')"
    fi
else
    test_result 1 "Config: sandbox/pacs-ai-backend/api-pacs/.env not found"
fi

# Check frontend .env configuration
if [ -f "sandbox/PACS-AI/platform/app/.env" ]; then
    API_URL=$(grep "^APP_PUBLIC_API_URL=" sandbox/PACS-AI/platform/app/.env | cut -d'=' -f2)
    if echo "$API_URL" | grep -q "localhost/api"; then
        test_result 0 "Config: Frontend APP_PUBLIC_API_URL contains 'localhost/api'"
    else
        test_result 1 "Config: Frontend APP_PUBLIC_API_URL is '$API_URL' (should contain 'localhost/api')"
    fi
else
    test_result 1 "Config: sandbox/PACS-AI/platform/app/.env not found"
fi

echo ""
echo "8. BROWSER ACCESSIBILITY TEST"
echo "-------------------------------------------"

# Test if we can GET the login page
curl -s http://localhost:3000 | grep -q "<!doctype html>" &>/dev/null
test_result $? "Browser: Frontend HTML page loads"

# Test if API is reachable from browser perspective (through nginx)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/v1/public?tenantId=prod-8o546 2>/dev/null || echo "000")
if [ "$HTTP_CODE" != "000" ]; then
    test_result 0 "Browser: Can reach /api/v1/public endpoint (HTTP $HTTP_CODE)"
else
    test_result 1 "Browser: Cannot reach /api/v1/public endpoint (connection refused)"
fi

echo ""
echo "================================================"
echo "SUMMARY"
echo "================================================"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All tests passed! PACS-AI is properly configured.${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Please review the errors above.${NC}"
    echo ""
    echo "Common issues:"
    echo "  - If api-pacs or nginx are restarting: Check container logs"
    echo "  - If REDIS_HOST is 'localhost': Regenerate sandbox with: bash scripts/02-create-sandbox.sh sandbox"
    echo "  - If containers can't communicate: Check Docker networks with: docker network inspect pacs-net-default"
    exit 1
fi
