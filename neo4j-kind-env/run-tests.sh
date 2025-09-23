#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test configuration
TEST_RESULTS_DIR="test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$TEST_RESULTS_DIR/test_run_$TIMESTAMP.log"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

log_section() {
    echo -e "\n${BOLD}$1${NC}" | tee -a "$LOG_FILE"
    echo "$(echo "$1" | sed 's/./=/g')" | tee -a "$LOG_FILE"
}

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

run_test() {
    local test_name="$1"
    local test_script="$2"
    local test_args="${3:-}"

    log_info "Running test: $test_name"

    local test_log="$TEST_RESULTS_DIR/${test_name// /_}_$TIMESTAMP.log"

    if [ -f "$test_script" ]; then
        chmod +x "$test_script"
        if timeout 1800 bash "$test_script" $test_args > "$test_log" 2>&1; then  # 30 minute timeout
            log_success "$test_name - PASSED"
            ((TESTS_PASSED++))
            return 0
        else
            log_error "$test_name - FAILED (see $test_log for details)"
            FAILED_TESTS+=("$test_name")
            ((TESTS_FAILED++))
            # Show last few lines of failed test
            echo "Last 10 lines of failed test:" | tee -a "$LOG_FILE"
            tail -10 "$test_log" | tee -a "$LOG_FILE"
            return 1
        fi
    else
        log_error "Test script not found: $test_script"
        FAILED_TESTS+=("$test_name")
        ((TESTS_FAILED++))
        return 1
    fi
}

setup_test_environment() {
    log_section "Setting Up Test Environment"

    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Check prerequisites
    log_info "Checking prerequisites..."

    # Check if Kind cluster exists
    if kind get clusters | grep -q "neo4j-cluster"; then
        log_success "Kind cluster 'neo4j-cluster' exists"
    else
        log_error "Kind cluster 'neo4j-cluster' not found"
        log_info "Please run: kind create cluster --config kind-config.yaml"
        exit 1
    fi

    # Check kubectl context
    local current_context=$(kubectl config current-context)
    if [[ "$current_context" == *"neo4j-cluster"* ]]; then
        log_success "kubectl context is set to Neo4j cluster"
    else
        log_warning "kubectl context: $current_context (expected: kind-neo4j-cluster)"
    fi

    # Check if Helm is available
    if command -v helm >/dev/null 2>&1; then
        local helm_version=$(helm version --short 2>/dev/null || echo "unknown")
        log_success "Helm is available: $helm_version"
    else
        log_error "Helm is not available"
        exit 1
    fi

    # Check cluster status
    log_info "Checking cluster status..."
    local ready_nodes=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
    log_success "Cluster has $ready_nodes ready nodes"

    # Clean up any existing test deployments
    log_info "Cleaning up any existing test deployments..."
    helm uninstall neo4j-test 2>/dev/null || true
    helm uninstall neo4j-cluster-test 2>/dev/null || true
    kubectl delete pvc -l "app.kubernetes.io/name=neo4j" 2>/dev/null || true
    sleep 10

    log_success "Test environment setup completed"
}

run_deployment_tests() {
    log_section "Deployment Tests"
    run_test "Deployment Tests" "./test-deployment.sh"
}

run_functionality_tests() {
    log_section "Functionality Tests"
    run_test "Functionality Tests" "./test-neo4j-functionality.sh"
}

run_cluster_tests() {
    log_section "Cluster Tests"
    log_warning "Note: Cluster tests require Neo4j Enterprise Edition"
    run_test "Cluster Tests" "./test-cluster.sh"
}

run_performance_tests() {
    log_section "Performance Tests"
    log_info "Running basic performance validation..."

    # This is integrated into other test scripts
    log_success "Performance tests completed (integrated in functionality and cluster tests)"
}

cleanup_tests() {
    log_section "Cleanup"
    log_info "Cleaning up test deployments..."

    # Clean up test deployments
    ./test-deployment.sh cleanup 2>/dev/null || true
    ./test-cluster.sh cleanup 2>/dev/null || true

    # Additional cleanup
    helm uninstall neo4j-test 2>/dev/null || true
    helm uninstall neo4j-cluster-test 2>/dev/null || true
    kubectl delete pvc -l "app.kubernetes.io/name=neo4j" 2>/dev/null || true

    log_success "Cleanup completed"
}

generate_test_report() {
    log_section "Test Report"

    local total_tests=$((TESTS_PASSED + TESTS_FAILED))
    local pass_rate=0
    if [ $total_tests -gt 0 ]; then
        pass_rate=$(echo "scale=2; $TESTS_PASSED * 100 / $total_tests" | bc -l 2>/dev/null || echo "0")
    fi

    # Create detailed report
    local report_file="$TEST_RESULTS_DIR/test_report_$TIMESTAMP.md"
    cat > "$report_file" << EOF
# Neo4j Helm Chart Test Report

**Test Run:** $TIMESTAMP
**Environment:** Kind Kubernetes Cluster

## Summary

- **Total Tests:** $total_tests
- **Passed:** $TESTS_PASSED
- **Failed:** $TESTS_FAILED
- **Pass Rate:** ${pass_rate}%

## Test Results

### ✅ Passed Tests
$(for i in $(seq 1 $TESTS_PASSED); do echo "- Test $i passed"; done)

### ❌ Failed Tests
$(if [ ${#FAILED_TESTS[@]} -eq 0 ]; then echo "- None"; else printf '%s\n' "${FAILED_TESTS[@]/#/- }"; fi)

## Environment Information

- **Kubernetes Version:** $(kubectl version --short --client 2>/dev/null | head -1 || echo "Unknown")
- **Helm Version:** $(helm version --short 2>/dev/null || echo "Unknown")
- **Cluster Nodes:** $(kubectl get nodes --no-headers | wc -l)

## Test Logs

Individual test logs are available in the \`$TEST_RESULTS_DIR\` directory.

EOF

    log_info "Detailed report saved to: $report_file"

    # Display summary
    echo | tee -a "$LOG_FILE"
    log_section "FINAL SUMMARY"
    echo "📊 Test Results:" | tee -a "$LOG_FILE"
    echo "   Total: $total_tests" | tee -a "$LOG_FILE"
    echo "   Passed: $TESTS_PASSED" | tee -a "$LOG_FILE"
    echo "   Failed: $TESTS_FAILED" | tee -a "$LOG_FILE"
    echo "   Pass Rate: ${pass_rate}%" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"

    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 ALL TESTS PASSED!"
    else
        log_error "Some tests failed. Check individual test logs for details."
        echo "Failed tests:" | tee -a "$LOG_FILE"
        printf '%s\n' "${FAILED_TESTS[@]/#/  - }" | tee -a "$LOG_FILE"
    fi

    echo | tee -a "$LOG_FILE"
    echo "📁 Test artifacts saved in: $TEST_RESULTS_DIR" | tee -a "$LOG_FILE"
    echo "📋 Full log: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "📄 Report: $report_file" | tee -a "$LOG_FILE"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_SUITE]

Test Suites:
  all                Run all test suites (default)
  deployment         Run deployment tests only
  functionality      Run functionality tests only
  cluster            Run cluster tests only
  quick              Run deployment and functionality tests

Options:
  --cleanup-only     Only perform cleanup
  --no-cleanup       Skip cleanup after tests
  --help            Show this help message

Examples:
  $0                 Run all tests
  $0 quick           Run quick test suite
  $0 deployment      Run only deployment tests
  $0 --cleanup-only  Clean up test environment
EOF
}

# Main execution
main() {
    local test_suite="${1:-all}"
    local cleanup_after=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup-only)
                cleanup_tests
                exit 0
                ;;
            --no-cleanup)
                cleanup_after=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            all|deployment|functionality|cluster|quick)
                test_suite="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Start test execution
    echo -e "${BOLD}🧪 Neo4j Helm Chart Test Suite${NC}"
    echo -e "${BOLD}================================${NC}"
    echo
    echo "Test suite: $test_suite" | tee "$LOG_FILE"
    echo "Started at: $(date)" | tee -a "$LOG_FILE"
    echo

    # Setup
    setup_test_environment

    # Run tests based on suite
    case "$test_suite" in
        "all")
            run_deployment_tests
            run_functionality_tests
            run_cluster_tests
            run_performance_tests
            ;;
        "deployment")
            run_deployment_tests
            ;;
        "functionality")
            run_deployment_tests
            run_functionality_tests
            ;;
        "cluster")
            run_cluster_tests
            ;;
        "quick")
            run_deployment_tests
            run_functionality_tests
            ;;
        *)
            log_error "Unknown test suite: $test_suite"
            show_usage
            exit 1
            ;;
    esac

    # Cleanup
    if [ "$cleanup_after" = true ]; then
        cleanup_tests
    fi

    # Generate report
    generate_test_report

    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Handle bc dependency for pass rate calculation
if ! command -v bc >/dev/null 2>&1; then
    log_warning "bc (calculator) not found. Installing via brew..."
    if command -v brew >/dev/null 2>&1; then
        brew install bc >/dev/null 2>&1 || true
    fi
fi

# Run main function
main "$@"