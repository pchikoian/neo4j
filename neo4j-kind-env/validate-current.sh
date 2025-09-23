#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

echo "🔍 Quick Validation of Current Neo4j Deployment"
echo "=============================================="
echo

# Check if any Neo4j pods exist
log_info "Checking for Neo4j deployments..."
pods=$(kubectl get pods -l app.kubernetes.io/name=neo4j --no-headers 2>/dev/null || echo "")

if [ -z "$pods" ]; then
    log_warning "No Neo4j pods found"
    echo
    log_info "Available test scripts:"
    echo "  ./run-tests.sh quick          - Run deployment and functionality tests"
    echo "  ./test-deployment.sh          - Test single instance deployment"
    echo "  ./test-cluster.sh             - Test multi-pod cluster (enterprise)"
    echo
    exit 0
fi

echo "Found Neo4j pods:"
kubectl get pods -l app.kubernetes.io/name=neo4j
echo

# Check pod status
ready_pods=$(kubectl get pods -l app.kubernetes.io/name=neo4j --no-headers | grep "1/1.*Running" | wc -l)
total_pods=$(kubectl get pods -l app.kubernetes.io/name=neo4j --no-headers | wc -l)

if [ "$ready_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
    log_success "All $total_pods Neo4j pods are ready"

    # Test basic connectivity
    pod_name=$(kubectl get pods -l app.kubernetes.io/name=neo4j -o jsonpath='{.items[0].metadata.name}')
    log_info "Testing connectivity to $pod_name..."

    # Test HTTP endpoint
    if kubectl exec "$pod_name" -- curl -s -f http://localhost:7474/ >/dev/null 2>&1; then
        log_success "Neo4j HTTP endpoint is responding"
    else
        log_warning "Neo4j HTTP endpoint not responding"
    fi

    # Get password and test cypher-shell
    release_name=$(kubectl get pods -l app.kubernetes.io/name=neo4j -o jsonpath='{.items[0].metadata.labels.app\.kubernetes\.io/instance}')
    if [ -n "$release_name" ]; then
        password=$(kubectl get secret "$release_name" -o jsonpath='{.data.neo4j-password}' 2>/dev/null | base64 --decode 2>/dev/null || echo "")
        if [ -n "$password" ]; then
            log_success "Retrieved Neo4j password"

            # Test cypher query
            result=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" "RETURN 'validation' as test;" 2>/dev/null || echo "FAILED")
            if [[ "$result" == *"validation"* ]]; then
                log_success "Cypher-shell is working"
            else
                log_warning "Cypher-shell test failed"
            fi
        else
            log_warning "Could not retrieve Neo4j password"
        fi
    fi

    echo
    log_success "Current deployment appears to be working!"
    echo
    echo "🔗 To access Neo4j:"
    echo "  kubectl port-forward svc/$release_name 7474:7474 7687:7687"
    echo "  Then visit: http://localhost:7474"
    echo "  Username: neo4j"
    echo "  Password: $password"

else
    log_warning "$ready_pods/$total_pods pods are ready"
    echo
    log_info "Pod details:"
    kubectl describe pods -l app.kubernetes.io/name=neo4j | grep -E "(Name|Status|Conditions)" | head -20
fi

echo
log_info "To run comprehensive tests:"
echo "  ./run-tests.sh quick    - Quick test suite"
echo "  ./run-tests.sh all      - Full test suite"