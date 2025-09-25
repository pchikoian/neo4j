#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME="neo4j-cluster"
CONFIG_FILE="kind-config.yaml"

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

# Check if Kind is installed
check_kind() {
    if ! command -v kind &> /dev/null; then
        log_error "Kind is not installed. Please install it first:"
        echo "  # For Linux/macOS"
        echo "  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64"
        echo "  chmod +x ./kind"
        echo "  sudo mv ./kind /usr/local/bin/kind"
        exit 1
    fi
    log_success "Kind is installed"
}

# Check if kubectl is installed
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first:"
        echo "  # For Linux"
        echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
        echo "  chmod +x kubectl"
        echo "  sudo mv kubectl /usr/local/bin/"
        exit 1
    fi
    log_success "kubectl is installed"
}

# Check if cluster already exists
check_existing_cluster() {
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        log_warning "Cluster '$CLUSTER_NAME' already exists"
        read -p "Do you want to delete it and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing cluster..."
            kind delete cluster --name "$CLUSTER_NAME"
            log_success "Existing cluster deleted"
        else
            log_info "Using existing cluster"
            return 0
        fi
    fi
}

# Create Kind cluster
create_cluster() {
    log_info "Creating Kind cluster '$CLUSTER_NAME'..."

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file '$CONFIG_FILE' not found!"
        exit 1
    fi

    if kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG_FILE"; then
        log_success "Kind cluster '$CLUSTER_NAME' created successfully"
    else
        log_error "Failed to create Kind cluster"
        exit 1
    fi
}

# Wait for cluster to be ready
wait_for_cluster() {
    log_info "Waiting for cluster to be ready..."

    # Wait for nodes to be ready
    local timeout=120
    local start_time=$(date +%s)

    while true; do
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l || echo "0")
        local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt "0" ]; then
            log_success "All $total_nodes nodes are ready!"
            break
        fi

        if [ $elapsed -gt $timeout ]; then
            log_error "Timeout waiting for cluster to be ready"
            kubectl get nodes
            exit 1
        fi

        echo -n "."
        sleep 5
    done
}

# Display cluster information
show_cluster_info() {
    echo
    log_success "Kind cluster is ready! 🎉"
    echo
    echo "📊 Cluster Information:"
    echo "======================"
    kubectl cluster-info
    echo
    echo "🔗 Nodes:"
    kubectl get nodes -o wide
    echo
    echo "🌐 Port Mappings (from kind-config.yaml):"
    echo "  Neo4j HTTP: http://localhost:7474"
    echo "  Neo4j Bolt: bolt://localhost:7687"
    echo
    echo "🚀 Next Steps:"
    echo "  1. Deploy Neo4j: ./run-tests.sh"
    echo "  2. Test cluster: ./test-cluster.sh"
    echo "  3. Check deployment: ./check-deployment.sh"
}

# Main function
main() {
    echo "🚀 Kind Cluster Setup for Neo4j Testing"
    echo "========================================"
    echo

    check_kind
    check_kubectl
    check_existing_cluster
    create_cluster
    wait_for_cluster
    show_cluster_info
}

# Handle cleanup
cleanup() {
    log_info "Cleaning up Kind cluster..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        kind delete cluster --name "$CLUSTER_NAME"
        log_success "Kind cluster '$CLUSTER_NAME' deleted"
    else
        log_warning "Cluster '$CLUSTER_NAME' does not exist"
    fi
}

# Handle script arguments
case "${1:-}" in
    "cleanup"|"delete")
        cleanup
        ;;
    "info")
        if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
            kubectl cluster-info
            kubectl get nodes -o wide
        else
            log_error "Cluster '$CLUSTER_NAME' does not exist"
        fi
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [cleanup|delete|info]"
        echo "  cleanup/delete - Delete the Kind cluster"
        echo "  info          - Show cluster information"
        echo ""
        echo "Default: Start Kind cluster for Neo4j testing"
        exit 1
        ;;
esac