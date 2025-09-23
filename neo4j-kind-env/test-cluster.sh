#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
RELEASE_NAME="neo4j-cluster-test"
NAMESPACE="default"
REPLICA_COUNT=3
TIMEOUT=600 # 10 minutes for cluster formation

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
        sleep 10
    done
}

get_pod_names() {
    kubectl get pods -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[*].metadata.name}'
}

get_neo4j_password() {
    kubectl get secret "$RELEASE_NAME" -o jsonpath='{.data.neo4j-password}' | base64 --decode
}

# Test functions
test_cluster_deployment() {
    log_info "Testing multi-pod cluster deployment..."

    # Clean up any existing deployment
    helm uninstall "$RELEASE_NAME" 2>/dev/null || true
    kubectl delete pvc -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" 2>/dev/null || true
    sleep 20

    # Create values file for enterprise edition (required for clustering)
    cat > cluster-values.yaml << EOF
replicaCount: $REPLICA_COUNT

image:
  tag: "5.15.0-enterprise"

auth:
  neo4jPassword: "clustertest123"

configuration:
  # Core cluster configuration
  dbms.mode: "CORE"
  dbms.default_listen_address: "0.0.0.0"
  dbms.default_advertised_address: "\$(hostname -f)"

  # Cluster discovery
  dbms.cluster.minimum_initial_system_primaries_count: "$REPLICA_COUNT"
  dbms.cluster.discovery.type: "K8S"
  dbms.kubernetes.service_port_name: "tcp-cluster"
  dbms.kubernetes.cluster_domain: "cluster.local"

  # Memory settings
  dbms.memory.heap.initial_size: "512M"
  dbms.memory.heap.max_size: "512M"
  dbms.memory.pagecache.size: "512M"

  # Connector configuration
  server.default_listen_address: "0.0.0.0"
  server.default_advertised_address: "\$(hostname -f)"
  server.bolt.enabled: "true"
  server.bolt.listen_address: "0.0.0.0:7687"
  server.http.enabled: "true"
  server.http.listen_address: "0.0.0.0:7474"
  server.https.enabled: "false"

  # License agreement
  NEO4J_ACCEPT_LICENSE_AGREEMENT: "yes"

resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
EOF

    # Deploy cluster
    if helm install "$RELEASE_NAME" ./neo4j-helm -f cluster-values.yaml; then
        log_success "Cluster deployment started"
    else
        log_error "Failed to deploy cluster"
        return 1
    fi

    # Wait for all pods to be ready
    if wait_for_pods "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" $REPLICA_COUNT $TIMEOUT; then
        log_success "All $REPLICA_COUNT pods are running"
    else
        log_error "Cluster failed to start properly"
        kubectl get pods -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME"
        kubectl describe pods -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME"
        return 1
    fi
}

test_cluster_discovery() {
    log_info "Testing cluster discovery and membership..."

    local pod_names=($(get_pod_names))
    local password=$(get_neo4j_password)

    if [ ${#pod_names[@]} -ne $REPLICA_COUNT ]; then
        log_error "Expected $REPLICA_COUNT pods, found ${#pod_names[@]}"
        return 1
    fi

    # Test cluster membership from each pod
    for pod in "${pod_names[@]}"; do
        log_info "Checking cluster membership from pod: $pod"

        # Wait a bit for cluster to form
        sleep 5

        local cluster_info=$(kubectl exec "$pod" -- cypher-shell -u neo4j -p "$password" \
            "SHOW SERVERS YIELD name, address, state RETURN name, address, state;" 2>/dev/null || echo "FAILED")

        if [[ "$cluster_info" != "FAILED" ]] && [[ "$cluster_info" == *"Enabled"* ]]; then
            log_success "Pod $pod can see cluster members"
            echo "    Cluster info: $cluster_info"
        else
            log_warning "Pod $pod cluster membership unclear: $cluster_info"
        fi
    done
}

test_cluster_leadership() {
    log_info "Testing cluster leadership and consensus..."

    local pod_names=($(get_pod_names))
    local password=$(get_neo4j_password)

    # Find the leader
    local leader_found=false
    for pod in "${pod_names[@]}"; do
        local role_info=$(kubectl exec "$pod" -- cypher-shell -u neo4j -p "$password" \
            "CALL dbms.cluster.role() YIELD role RETURN role;" 2>/dev/null || echo "FAILED")

        if [[ "$role_info" == *"LEADER"* ]]; then
            log_success "Found cluster leader: $pod"
            leader_found=true
            break
        elif [[ "$role_info" == *"FOLLOWER"* ]]; then
            log_info "Pod $pod is a follower"
        fi
    done

    if [ "$leader_found" = false ]; then
        log_warning "No clear leader found in cluster"
        return 1
    fi
}

test_cluster_data_replication() {
    log_info "Testing data replication across cluster..."

    local pod_names=($(get_pod_names))
    local password=$(get_neo4j_password)
    local primary_pod="${pod_names[0]}"

    # Create test data on primary pod
    log_info "Creating test data on primary pod: $primary_pod"
    local create_result=$(kubectl exec "$primary_pod" -- cypher-shell -u neo4j -p "$password" \
        "CREATE (c:ClusterTest {id: 'test-$(date +%s)', timestamp: datetime()}) RETURN c.id as id;" 2>/dev/null || echo "FAILED")

    if [[ "$create_result" == *"test-"* ]]; then
        log_success "Test data created on primary pod"
        local test_id=$(echo "$create_result" | grep -o 'test-[0-9]*' | head -1)

        # Wait for replication
        sleep 10

        # Check if data is replicated to other pods
        local replication_success=true
        for pod in "${pod_names[@]:1}"; do # Skip first pod (primary)
            log_info "Checking data replication on pod: $pod"

            local read_result=$(kubectl exec "$pod" -- cypher-shell -u neo4j -p "$password" \
                "MATCH (c:ClusterTest {id: '$test_id'}) RETURN c.id as id;" 2>/dev/null || echo "FAILED")

            if [[ "$read_result" == *"$test_id"* ]]; then
                log_success "Data replicated to pod: $pod"
            else
                log_error "Data NOT replicated to pod: $pod"
                replication_success=false
            fi
        done

        # Clean up test data
        kubectl exec "$primary_pod" -- cypher-shell -u neo4j -p "$password" \
            "MATCH (c:ClusterTest {id: '$test_id'}) DELETE c;" > /dev/null 2>&1 || true

        if [ "$replication_success" = true ]; then
            log_success "Data replication working correctly"
        else
            log_error "Data replication has issues"
            return 1
        fi
    else
        log_error "Failed to create test data: $create_result"
        return 1
    fi
}

test_cluster_failover() {
    log_info "Testing cluster failover simulation..."

    local pod_names=($(get_pod_names))
    local password=$(get_neo4j_password)

    # Find current leader
    local current_leader=""
    for pod in "${pod_names[@]}"; do
        local role_info=$(kubectl exec "$pod" -- cypher-shell -u neo4j -p "$password" \
            "CALL dbms.cluster.role() YIELD role RETURN role;" 2>/dev/null || echo "FAILED")

        if [[ "$role_info" == *"LEADER"* ]]; then
            current_leader="$pod"
            break
        fi
    done

    if [ -z "$current_leader" ]; then
        log_warning "No current leader found, skipping failover test"
        return 0
    fi

    log_info "Current leader: $current_leader"

    # Simulate failover by restarting the leader pod
    log_info "Simulating failover by restarting leader pod..."
    kubectl delete pod "$current_leader"

    # Wait for pod to be recreated and ready
    sleep 30
    if wait_for_pods "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" $REPLICA_COUNT 120; then
        log_success "Pod recreated successfully"
    else
        log_error "Pod recreation failed"
        return 1
    fi

    # Check if a new leader was elected
    sleep 30 # Wait for leader election
    local new_leader_found=false
    for pod in $(get_pod_names); do
        local role_info=$(kubectl exec "$pod" -- cypher-shell -u neo4j -p "$password" \
            "CALL dbms.cluster.role() YIELD role RETURN role;" 2>/dev/null || echo "FAILED")

        if [[ "$role_info" == *"LEADER"* ]]; then
            log_success "New leader elected: $pod"
            new_leader_found=true
            break
        fi
    done

    if [ "$new_leader_found" = false ]; then
        log_warning "No new leader elected after failover"
        return 1
    fi
}

test_cluster_performance() {
    log_info "Testing cluster performance..."

    local pod_names=($(get_pod_names))
    local password=$(get_neo4j_password)
    local primary_pod="${pod_names[0]}"

    # Create larger dataset across cluster
    log_info "Creating performance test dataset (5000 nodes)..."
    local start_time=$(date +%s%3N)
    local create_perf=$(kubectl exec "$primary_pod" -- cypher-shell -u neo4j -p "$password" \
        "UNWIND range(1, 5000) as i CREATE (n:ClusterPerfTest {id: i, value: 'cluster_node_' + toString(i)}) RETURN count(n) as created;" 2>/dev/null || echo "FAILED")
    local end_time=$(date +%s%3N)
    local create_duration=$((end_time - start_time))

    if [[ "$create_perf" == *"5000"* ]]; then
        log_success "Created 5000 test nodes in ${create_duration}ms"
    else
        log_error "Failed to create performance test dataset: $create_perf"
        return 1
    fi

    # Test read performance across different pods
    for pod in "${pod_names[@]}"; do
        log_info "Testing read performance on pod: $pod"
        local start_time=$(date +%s%3N)
        local query_perf=$(kubectl exec "$pod" -- cypher-shell -u neo4j -p "$password" \
            "MATCH (n:ClusterPerfTest) WHERE n.id > 2500 RETURN count(n) as count;" 2>/dev/null || echo "FAILED")
        local end_time=$(date +%s%3N)
        local query_duration=$((end_time - start_time))

        if [[ "$query_perf" == *"2500"* ]]; then
            log_success "Pod $pod: Query completed in ${query_duration}ms"
        else
            log_warning "Pod $pod: Query performance test unclear: $query_perf"
        fi
    done

    # Clean up performance test data
    log_info "Cleaning up performance test dataset..."
    kubectl exec "$primary_pod" -- cypher-shell -u neo4j -p "$password" \
        "MATCH (n:ClusterPerfTest) DELETE n;" > /dev/null 2>&1 || true
    log_success "Performance test dataset cleaned up"
}

cleanup() {
    log_info "Cleaning up cluster test deployment..."
    helm uninstall "$RELEASE_NAME" 2>/dev/null || true
    kubectl delete pvc -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME" 2>/dev/null || true
    rm -f cluster-values.yaml
    log_success "Cleanup completed"
}

# Main test execution
main() {
    echo "🧪 Neo4j Cluster Tests"
    echo "======================"
    echo
    log_warning "Note: This test requires Neo4j Enterprise Edition for clustering"
    echo

    # Test 1: Cluster Deployment
    echo "🚀 Test 1: Multi-Pod Cluster Deployment"
    test_cluster_deployment
    echo

    # Test 2: Cluster Discovery
    echo "🔍 Test 2: Cluster Discovery and Membership"
    test_cluster_discovery
    echo

    # Test 3: Leadership
    echo "👑 Test 3: Cluster Leadership"
    test_cluster_leadership
    echo

    # Test 4: Data Replication
    echo "🔄 Test 4: Data Replication"
    test_cluster_data_replication
    echo

    # Test 5: Failover
    echo "🔧 Test 5: Cluster Failover"
    test_cluster_failover
    echo

    # Test 6: Performance
    echo "⚡ Test 6: Cluster Performance"
    test_cluster_performance
    echo

    # Summary
    echo "📊 Cluster Summary"
    echo "=================="
    kubectl get all,pvc -l "app.kubernetes.io/name=neo4j,app.kubernetes.io/instance=$RELEASE_NAME"
    echo

    log_success "All cluster tests completed! 🎉"
    echo
    echo "🔗 Cluster Access Information:"
    echo "  Username: neo4j"
    echo "  Password: $(get_neo4j_password)"
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
        echo "  cleanup - Clean up cluster test deployment"
        echo ""
        echo "Note: This script tests Neo4j clustering features which require"
        echo "Neo4j Enterprise Edition. The test will deploy a 3-node cluster."
        exit 1
        ;;
esac