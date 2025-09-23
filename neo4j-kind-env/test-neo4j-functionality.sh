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

get_neo4j_password() {
    kubectl get secret "$RELEASE_NAME" -o jsonpath='{.data.neo4j-password}' | base64 --decode
}

get_pod_name() {
    kubectl get pods -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}'
}

# Test functions
test_neo4j_connectivity() {
    log_info "Testing Neo4j connectivity..."

    local pod_name=$(get_pod_name)
    if [ -z "$pod_name" ]; then
        log_error "No Neo4j pod found"
        return 1
    fi

    # Test HTTP endpoint
    log_info "Testing HTTP endpoint (port 7474)..."
    if kubectl exec "$pod_name" -- curl -s -f http://localhost:7474/ > /dev/null; then
        log_success "HTTP endpoint is accessible"
    else
        log_error "HTTP endpoint is not accessible"
        return 1
    fi

    # Test if Neo4j browser is responding
    log_info "Testing Neo4j Browser endpoint..."
    local response=$(kubectl exec "$pod_name" -- curl -s http://localhost:7474/browser/ | head -1)
    if [[ "$response" == *"html"* ]] || [[ "$response" == *"<!DOCTYPE"* ]]; then
        log_success "Neo4j Browser is responding"
    else
        log_warning "Neo4j Browser response unclear: $response"
    fi
}

test_cypher_queries() {
    log_info "Testing Cypher query execution..."

    local pod_name=$(get_pod_name)
    local password=$(get_neo4j_password)

    if [ -z "$pod_name" ] || [ -z "$password" ]; then
        log_error "Pod name or password not found"
        return 1
    fi

    # Test basic connectivity with cypher-shell
    log_info "Testing cypher-shell connectivity..."
    local cypher_test=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" "RETURN 'Hello Neo4j' as greeting;" 2>/dev/null || echo "FAILED")

    if [[ "$cypher_test" == *"Hello Neo4j"* ]]; then
        log_success "Cypher-shell is working"
    else
        log_error "Cypher-shell connection failed"
        log_error "Response: $cypher_test"
        return 1
    fi

    # Test creating and querying data
    log_info "Testing data creation and querying..."

    # Create test data
    local create_result=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "CREATE (p:Person {name: 'Test User', age: 30}) RETURN p.name as name;" 2>/dev/null || echo "FAILED")

    if [[ "$create_result" == *"Test User"* ]]; then
        log_success "Data creation successful"
    else
        log_error "Data creation failed: $create_result"
        return 1
    fi

    # Query test data
    local query_result=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "MATCH (p:Person {name: 'Test User'}) RETURN p.name as name, p.age as age;" 2>/dev/null || echo "FAILED")

    if [[ "$query_result" == *"Test User"* ]] && [[ "$query_result" == *"30"* ]]; then
        log_success "Data querying successful"
    else
        log_error "Data querying failed: $query_result"
        return 1
    fi

    # Clean up test data
    kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "MATCH (p:Person {name: 'Test User'}) DELETE p;" > /dev/null 2>&1 || true
}

test_neo4j_api() {
    log_info "Testing Neo4j REST API..."

    local pod_name=$(get_pod_name)
    local password=$(get_neo4j_password)

    # Test authentication
    log_info "Testing API authentication..."
    local auth_response=$(kubectl exec "$pod_name" -- curl -s -u "neo4j:$password" \
        -H "Content-Type: application/json" \
        http://localhost:7474/db/data/ 2>/dev/null || echo "FAILED")

    if [[ "$auth_response" == *"neo4j_version"* ]]; then
        log_success "API authentication successful"
    else
        log_error "API authentication failed"
        return 1
    fi

    # Test transaction endpoint
    log_info "Testing transaction endpoint..."
    local tx_response=$(kubectl exec "$pod_name" -- curl -s -u "neo4j:$password" \
        -H "Content-Type: application/json" \
        -X POST \
        -d '{"statements":[{"statement":"RETURN 1 as result"}]}' \
        http://localhost:7474/db/data/transaction/commit 2>/dev/null || echo "FAILED")

    if [[ "$tx_response" == *"result"* ]] && [[ "$tx_response" == *"1"* ]]; then
        log_success "Transaction API working"
    else
        log_error "Transaction API failed"
        return 1
    fi
}

test_performance_basic() {
    log_info "Testing basic performance..."

    local pod_name=$(get_pod_name)
    local password=$(get_neo4j_password)

    # Create a larger dataset for performance testing
    log_info "Creating test dataset (1000 nodes)..."
    local create_perf=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "UNWIND range(1, 1000) as i CREATE (n:TestNode {id: i, value: 'node_' + toString(i)}) RETURN count(n) as created;" 2>/dev/null || echo "FAILED")

    if [[ "$create_perf" == *"1000"* ]]; then
        log_success "Created 1000 test nodes"
    else
        log_error "Failed to create test dataset: $create_perf"
        return 1
    fi

    # Test query performance
    log_info "Testing query performance..."
    local start_time=$(date +%s%3N)
    local query_perf=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "MATCH (n:TestNode) WHERE n.id > 500 RETURN count(n) as count;" 2>/dev/null || echo "FAILED")
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [[ "$query_perf" == *"500"* ]]; then
        log_success "Query completed in ${duration}ms (returned 500 nodes)"
    else
        log_error "Query performance test failed: $query_perf"
        return 1
    fi

    # Clean up test data
    log_info "Cleaning up test dataset..."
    kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "MATCH (n:TestNode) DELETE n;" > /dev/null 2>&1 || true
    log_success "Test dataset cleaned up"
}

test_database_info() {
    log_info "Testing database information retrieval..."

    local pod_name=$(get_pod_name)
    local password=$(get_neo4j_password)

    # Get Neo4j version
    local version_info=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "CALL dbms.components() YIELD name, versions RETURN name, versions[0] as version;" 2>/dev/null || echo "FAILED")

    if [[ "$version_info" == *"Neo4j Kernel"* ]]; then
        log_success "Database version info retrieved"
        echo "    $version_info"
    else
        log_error "Failed to get version info: $version_info"
        return 1
    fi

    # Get database statistics
    local db_stats=$(kubectl exec "$pod_name" -- cypher-shell -u neo4j -p "$password" \
        "CALL db.stats.retrieve('GRAPH COUNTS') YIELD data RETURN data.nodes as nodes, data.relationships as relationships;" 2>/dev/null || echo "FAILED")

    if [[ "$db_stats" != "FAILED" ]]; then
        log_success "Database statistics retrieved"
        echo "    $db_stats"
    else
        log_warning "Could not retrieve database statistics"
    fi
}

test_bolt_connectivity() {
    log_info "Testing Bolt protocol connectivity..."

    local pod_name=$(get_pod_name)

    # Check if Bolt port is listening
    local bolt_check=$(kubectl exec "$pod_name" -- netstat -ln | grep ":7687" | head -1)
    if [[ "$bolt_check" == *"LISTEN"* ]]; then
        log_success "Bolt port (7687) is listening"
    else
        log_error "Bolt port (7687) is not listening"
        return 1
    fi

    # Test Bolt connection (basic check)
    local bolt_test=$(kubectl exec "$pod_name" -- timeout 5 bash -c 'echo | nc localhost 7687' 2>/dev/null || echo "FAILED")
    if [[ "$bolt_test" != "FAILED" ]]; then
        log_success "Bolt port is accessible"
    else
        log_warning "Bolt port connection test inconclusive"
    fi
}

# Main test execution
main() {
    echo "🧪 Neo4j Functionality Tests"
    echo "============================"
    echo

    # Check if deployment exists
    local pod_name=$(get_pod_name)
    if [ -z "$pod_name" ]; then
        log_error "No Neo4j deployment found. Please run deployment tests first."
        exit 1
    fi

    # Wait for pod to be ready
    log_info "Waiting for Neo4j pod to be ready..."
    local ready=$(kubectl get pod "$pod_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$ready" != "True" ]; then
        log_error "Neo4j pod is not ready. Please wait for deployment to complete."
        exit 1
    fi

    echo "🔍 Test 1: Connectivity Tests"
    test_neo4j_connectivity
    test_bolt_connectivity
    echo

    echo "💾 Test 2: Database Operations"
    test_cypher_queries
    test_neo4j_api
    echo

    echo "📊 Test 3: Performance and Info"
    test_performance_basic
    test_database_info
    echo

    log_success "All functionality tests passed! 🎉"
    echo
    echo "🔗 Connection Information:"
    echo "  HTTP URL: http://localhost:7474 (after port-forward)"
    echo "  Bolt URL: bolt://localhost:7687 (after port-forward)"
    echo "  Username: neo4j"
    echo "  Password: $(get_neo4j_password)"
    echo
    echo "📝 To access Neo4j:"
    echo "  kubectl port-forward svc/$RELEASE_NAME 7474:7474 7687:7687"
}

# Handle script arguments
case "${1:-}" in
    "")
        main
        ;;
    *)
        echo "Usage: $0"
        echo "Tests Neo4j functionality including connectivity, queries, and performance"
        exit 1
        ;;
esac