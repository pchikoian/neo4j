# Neo4j Helm Chart Test Suite

This directory contains comprehensive test scripts for validating the Neo4j Helm chart deployment and functionality.

## 📋 Test Scripts Overview

### 🚀 Main Test Runner
- **`run-tests.sh`** - Comprehensive test suite orchestrator
  - Runs all tests in sequence
  - Generates detailed reports
  - Supports different test suites
  - Handles cleanup and logging

### 🔧 Individual Test Scripts

#### 1. **`test-deployment.sh`** - Deployment Tests
- Validates Helm chart structure and templates
- Tests single instance deployment
- Verifies Kubernetes resources (services, PVCs, secrets)
- Checks pod health and readiness
- **Usage:** `./test-deployment.sh`

#### 2. **`test-neo4j-functionality.sh`** - Functionality Tests
- Tests Neo4j connectivity (HTTP and Bolt)
- Validates Cypher query execution
- Tests REST API functionality
- Basic performance testing
- Database information retrieval
- **Usage:** `./test-neo4j-functionality.sh`

#### 3. **`test-cluster.sh`** - Cluster Tests
- Tests multi-pod Neo4j cluster deployment
- Validates cluster discovery and membership
- Tests leadership election and consensus
- Verifies data replication across nodes
- Simulates failover scenarios
- **Usage:** `./test-cluster.sh`
- **Note:** Requires Neo4j Enterprise Edition

### 🔍 Utility Scripts

#### 4. **`validate-current.sh`** - Quick Validation
- Quick health check of current deployment
- Basic connectivity testing
- **Usage:** `./validate-current.sh`

#### 5. **`check-deployment.sh`** - Status Check
- Shows deployment status
- Provides access instructions
- **Usage:** `./check-deployment.sh`

## 🎯 Quick Start

### Run All Tests
```bash
./run-tests.sh
```

### Run Quick Test Suite (Recommended)
```bash
./run-tests.sh quick
```

### Run Specific Test Types
```bash
# Only deployment tests
./run-tests.sh deployment

# Only functionality tests
./run-tests.sh functionality

# Only cluster tests (requires enterprise)
./run-tests.sh cluster
```

### Validate Current Deployment
```bash
./validate-current.sh
```

## 📊 Test Suites

### 1. **Quick Suite** (`quick`)
- ✅ Deployment tests
- ✅ Functionality tests
- ⏱️ ~5-10 minutes

### 2. **Full Suite** (`all`)
- ✅ Deployment tests
- ✅ Functionality tests
- ✅ Cluster tests (enterprise)
- ✅ Performance validation
- ⏱️ ~20-30 minutes

## 🧪 Test Categories

### Deployment Tests
- [x] Helm chart linting
- [x] Template rendering
- [x] Single instance deployment
- [x] Service creation and endpoints
- [x] Persistent storage
- [x] Secrets and ConfigMaps
- [x] Pod health checks

### Functionality Tests
- [x] HTTP endpoint connectivity
- [x] Bolt protocol connectivity
- [x] Cypher query execution
- [x] REST API functionality
- [x] Data creation and querying
- [x] Basic performance testing
- [x] Database information retrieval

### Cluster Tests (Enterprise)
- [x] Multi-pod deployment
- [x] Cluster discovery
- [x] Leadership election
- [x] Data replication
- [x] Failover simulation
- [x] Cluster performance

## 📁 Test Results

Test results are saved in the `test-results/` directory:
- Individual test logs
- Detailed test reports (Markdown)
- Timestamps for each run

## 🔧 Test Configuration

### Environment Requirements
- Kind cluster running (`neo4j-cluster`)
- kubectl configured for the cluster
- Helm 3.8.0+
- Neo4j Helm chart in `./neo4j-helm/`

### Customization
Tests can be customized by modifying variables at the top of each script:
- Release names
- Timeouts
- Replica counts
- Resource limits

## 🛠️ Troubleshooting

### Common Issues

1. **Tests fail with "no cluster found"**
   ```bash
   kind create cluster --config kind-config.yaml
   ```

2. **Tests timeout waiting for pods**
   - Check cluster resources
   - Verify image pull is successful
   - Increase timeout values in scripts

3. **Cluster tests fail**
   - Enterprise edition required for clustering
   - Ensure sufficient cluster resources

### Debug Commands
```bash
# Check cluster status
kubectl get nodes

# Check Neo4j deployments
kubectl get all -l app.kubernetes.io/name=neo4j

# View pod logs
kubectl logs -l app.kubernetes.io/name=neo4j

# Describe problematic pods
kubectl describe pods -l app.kubernetes.io/name=neo4j
```

## 🧹 Cleanup

### Clean up test deployments
```bash
./run-tests.sh --cleanup-only
```

### Manual cleanup
```bash
helm uninstall neo4j-test neo4j-cluster-test
kubectl delete pvc -l app.kubernetes.io/name=neo4j
```

## 📈 Examples

### Continuous Integration
```bash
# Run in CI/CD pipeline
./run-tests.sh quick --no-cleanup
exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Tests failed - check logs"
    exit $exit_code
fi
```

### Development Testing
```bash
# Quick validation during development
./validate-current.sh

# Full functionality test after changes
./test-neo4j-functionality.sh
```

## 🎉 Success Criteria

Tests are considered successful when:
- All pods reach Running state
- Services have endpoints
- Neo4j responds to HTTP/Bolt connections
- Cypher queries execute successfully
- Data persistence works correctly
- (Cluster tests) All nodes join cluster and replicate data

## 📝 Notes

- Community edition supports single instance only
- Enterprise edition required for clustering features
- Tests automatically handle cleanup between runs
- Detailed logs preserved for debugging
- Performance tests provide baseline metrics