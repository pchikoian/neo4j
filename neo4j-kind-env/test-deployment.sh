#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
RELEASE_NAME="neo4j-test"
NAMESPACE="default"
TIMEOUT=300 # 5 minutes

# Helper functions
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

wait_for_pods() {
    local label_selector="$1"
    local expected_count="$2"
    local timeout="$3"

    log_info "Waiting for $expected_count pods with selector '$label_selector' to be ready (timeout: ${timeout}s)..."

    local start_time=$(date +%s)
    while true; do
        local ready_pods=$(kubectl get pods -l "$label_selector" --no-headers 2>/dev/null | grep "1/1.*Running" | wc -l || echo "0")
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$ready_pods" -eq "$expected_count" ]; then
            log_success "All $expected_count pods are ready!"
            return 0
        fi

        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for pods to be ready"
            kubectl get pods -l "$label_selector"
            return 1
        fi

        echo -n "."
        sleep 5
    done
}

# Test functions
test_helm_chart_lint() {
    log_info "Testing Helm chart linting..."
    if helm lint ./neo4j-helm; then
        log_success "Helm chart lint passed"
    else
        log_error "Helm chart lint failed"
        return 1
    fi
}

test_helm_template() {
    log_info "Testing Helm template rendering..."
    if helm template test-render ./neo4j-helm > /dev/null; then
        log_success "Helm template rendering passed"
    else
        log_error "Helm template rendering failed"
        return 1
    fi
}

test_single_instance_deployment() {
    log_info "Testing single instance deployment..."

    # Clean up any existing deployment
    helm uninstall "$RELEASE_NAME" 2>/dev/null || true
    sleep 10

    # Deploy single instance
    if helm install "$RELEASE_NAME" ./neo4j-helm --set replicaCount=1; then
        log_success "Single instance deployment started"
    else
        log_error "Failed to deploy single instance"
        return 1
    fi

    # Wait for pod to be ready
    if wait_for_pods "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" 1 $TIMEOUT; then
        log_success "Single instance is running"
    else
        log_error "Single instance failed to start"
        kubectl describe pods -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME"
        return 1
    fi
}

test_services() {
    log_info "Testing Kubernetes services..."

    # Check if services exist
    if kubectl get svc "$RELEASE_NAME" > /dev/null 2>&1; then
        log_success "Main service exists"
    else
        log_error "Main service not found"
        return 1
    fi

    if kubectl get svc "$RELEASE_NAME-headless" > /dev/null 2>&1; then
        log_success "Headless service exists"
    else
        log_error "Headless service not found"
        return 1
    fi

    # Check service endpoints
    local endpoints=$(kubectl get endpoints "$RELEASE_NAME" -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
    if [ "$endpoints" -gt 0 ]; then
        log_success "Service has $endpoints endpoint(s)"
    else
        log_warning "Service has no endpoints yet"
    fi
}

test_persistent_storage() {
    log_info "Testing persistent storage..."

    local pvcs=$(kubectl get pvc -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" --no-headers | wc -l)
    if [ "$pvcs" -gt 0 ]; then
        log_success "Found $pvcs PVC(s)"

        # Check if PVCs are bound
        local bound_pvcs=$(kubectl get pvc -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" --no-headers | grep "Bound" | wc -l)
        if [ "$bound_pvcs" -eq "$pvcs" ]; then
            log_success "All PVCs are bound"
        else
            log_warning "$bound_pvcs/$pvcs PVCs are bound"
        fi
    else
        log_error "No PVCs found"
        return 1
    fi
}

test_secrets_and_configmaps() {
    log_info "Testing secrets and configmaps..."

    # Check secret
    if kubectl get secret "$RELEASE_NAME" > /dev/null 2>&1; then
        log_success "Neo4j secret exists"

        # Verify password is set
        local password=$(kubectl get secret "$RELEASE_NAME" -o jsonpath='{.data.neo4j-password}' | base64 --decode)
        if [ -n "$password" ]; then
            log_success "Neo4j password is configured"
        else
            log_error "Neo4j password is empty"
            return 1
        fi
    else
        log_error "Neo4j secret not found"
        return 1
    fi

    # Check configmap
    if kubectl get configmap "$RELEASE_NAME-configuration" > /dev/null 2>&1; then
        log_success "Neo4j configmap exists"
    else
        log_warning "Neo4j configmap not found (might be using existing configmap)"
    fi
}

test_pod_health() {
    log_info "Testing pod health and readiness..."

    local pod_name=$(kubectl get pods -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$pod_name" ]; then
        # Check readiness probe
        local ready=$(kubectl get pod "$pod_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$ready" = "True" ]; then
            log_success "Pod $pod_name is ready"
        else
            log_error "Pod $pod_name is not ready"
            kubectl describe pod "$pod_name"
            return 1
        fi

        # Check if Neo4j is responding
        log_info "Testing Neo4j HTTP endpoint..."
        if kubectl exec "$pod_name" -- curl -s -f http://localhost:7474/ > /dev/null; then
            log_success "Neo4j HTTP endpoint is responding"
        else
            log_warning "Neo4j HTTP endpoint not responding yet"
        fi
    else
        log_error "No pods found"
        return 1
    fi
}

cleanup() {
    log_info "Cleaning up test deployment..."
    helm uninstall "$RELEASE_NAME" 2>/dev/null || true
    kubectl delete pvc -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" 2>/dev/null || true
    log_success "Cleanup completed"
}

# Main test execution
main() {
    echo "🧪 Neo4j Helm Chart Deployment Tests"
    echo "======================================"
    echo

    # Test 1: Helm Chart Validation
    echo "📋 Test 1: Helm Chart Validation"
    test_helm_chart_lint
    test_helm_template
    echo

    # Test 2: Single Instance Deployment
    echo "🚀 Test 2: Single Instance Deployment"
    test_single_instance_deployment
    echo

    # Test 3: Kubernetes Resources
    echo "☸️  Test 3: Kubernetes Resources"
    test_services
    test_persistent_storage
    test_secrets_and_configmaps
    echo

    # Test 4: Pod Health
    echo "🏥 Test 4: Pod Health and Readiness"
    test_pod_health
    echo

    # Summary
    echo "📊 Test Summary"
    echo "==============="
    kubectl get all,pvc,secrets,configmaps -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME"
    echo

    log_success "All deployment tests passed! 🎉"
    echo
    echo "🔗 Access Information:"
    echo "  Username: neo4j"
    echo "  Password: \$(kubectl get secret $RELEASE_NAME -o jsonpath='{.data.neo4j-password}' | base64 --decode)"
    echo "  Port Forward: kubectl port-forward svc/$RELEASE_NAME 7474:7474 7687:7687"
    echo "  Browser: http://localhost:7474"
}

# Handle script arguments
case "${1:-}" in
    "cleanup")
        cleanup
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [cleanup]"
        echo "  cleanup - Clean up test deployment"
        exit 1
        ;;
esac