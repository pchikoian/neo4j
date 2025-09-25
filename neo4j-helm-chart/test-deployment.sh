#!/bin/bash

set -e

CHART_NAME="neo4j-custom"
RELEASE_NAME="neo4j-test"
NAMESPACE="default"

echo "🧪 Testing Neo4j Helm Chart Deployment"
echo "========================================"

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if connected to a Kubernetes cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Not connected to a Kubernetes cluster. Please configure kubectl."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Update dependencies
echo "📦 Updating Helm dependencies..."
helm dependency update

# Validate the chart
echo "🔍 Validating Helm chart..."
helm lint .

# Dry run the deployment
echo "🧪 Running dry-run deployment..."
helm upgrade --install $RELEASE_NAME . --namespace $NAMESPACE --dry-run --debug

# Optional: Template rendering test
echo "📄 Testing template rendering..."
helm template $RELEASE_NAME . --namespace $NAMESPACE > /tmp/neo4j-manifests.yaml

echo "✅ Generated Kubernetes manifests:"
echo "   - Saved to: /tmp/neo4j-manifests.yaml"

# Check for required resources in templates
echo "🔍 Checking for required resources..."

if grep -q "kind: StatefulSet" /tmp/neo4j-manifests.yaml; then
    echo "   ✅ StatefulSet found"
else
    echo "   ❌ StatefulSet not found"
fi

if grep -q "kind: Service" /tmp/neo4j-manifests.yaml; then
    echo "   ✅ Service found"
else
    echo "   ❌ Service not found"
fi

if grep -q "clusterIP: None" /tmp/neo4j-manifests.yaml; then
    echo "   ✅ Headless service found"
else
    echo "   ❌ Headless service not found"
fi

# Actual deployment (optional - uncomment to deploy)
echo ""
read -p "🚀 Do you want to deploy the chart for real? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🚀 Deploying/Upgrading Neo4j chart..."
    helm upgrade --install $RELEASE_NAME . --namespace $NAMESPACE --wait --timeout 5m

    echo "✅ Deployment completed!"
    echo ""
    echo "📊 Checking deployment status..."
    kubectl get pods,svc -l app.kubernetes.io/name=neo4j -n $NAMESPACE

    echo ""
    echo "🔍 To check Neo4j status:"
    echo "  kubectl logs -f deployment/neo4j -n $NAMESPACE"
    echo ""
    echo "🧹 To cleanup:"
    echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
else
    echo "⏭️  Skipping actual deployment"
fi

echo ""
echo "✅ Test completed successfully!"