#!/bin/bash
echo "=== Neo4j Kind Environment Status ==="
echo

echo "🏷️ Cluster Information:"
kubectl cluster-info --context kind-neo4j-cluster
echo

echo "📋 Nodes:"
kubectl get nodes
echo

echo "🚀 Neo4j Deployment Status:"
kubectl get pods,svc,pvc -l app.kubernetes.io/name=neo4j
echo

echo "📊 Neo4j Helm Release:"
helm list
echo

if kubectl get pods -l app.kubernetes.io/name=neo4j | grep -q "1/1.*Running"; then
  echo "✅ Neo4j is running successfully!"
  echo
  echo "📝 To access Neo4j:"
  echo "1. Get the password:"
  echo "   export NEO4J_PASSWORD=\$(kubectl get secret neo4j-single -o jsonpath=\"{.data.neo4j-password}\" | base64 --decode)"
  echo
  echo "2. Port forward to access locally:"
  echo "   kubectl port-forward svc/neo4j-single 7474:7474 7687:7687"
  echo
  echo "3. Access Neo4j Browser at: http://localhost:7474"
  echo "   Username: neo4j"
  echo "   Password: \$NEO4J_PASSWORD"
else
  echo "⏳ Neo4j is still starting up. The image might still be downloading."
  echo "   Check again in a few minutes with: kubectl get pods -l app.kubernetes.io/name=neo4j"
fi