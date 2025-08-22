# Prerequisites Check
kind version
kubectl version --client
docker version

#################################################################################################################################

#Create Kind Cluster
# Delete existing cluster if any
kind delete cluster --name=apache-test

# Create cluster with port mapping
kind create cluster --config=create-cluster.yaml --name=apache-test

# Verify cluster
kubectl cluster-info --context kind-apache-test

#################################################################################################################################

#Install and Configure Metrics Server
# Clean up any existing metrics server
kubectl delete deployment metrics-server -n kube-system --ignore-not-found=true
kubectl delete service metrics-server -n kube-system --ignore-not-found=true
kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found=true

# Install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Configure for Kind cluster
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  },
  {
    "op": "add", 
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
  }
]'

# Wait for metrics server to be ready
kubectl wait --for=condition=available --timeout=300s deployment/metrics-server -n kube-system

#################################################################################################################################

#Install VPA
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh
cd ../../

#################################################################################################################################

#Deploy Application
# Apply all Kubernetes manifests
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f vpa.yaml

# Wait for deployment to be ready
kubectl wait --for=condition=available --timeout=300s deployment/apache-deployment -n apache

#################################################################################################################################

#Verify Setup
# Check all resources
kubectl get all -n apache

# Check vpa status
kubectl get vpa -n apache

# Test service accessibility
curl http://localhost:80

# Wait for metrics to be available (may take 1-2 minutes)
kubectl top nodes
kubectl top pods -n apache

#Start Monitoring (Run in separate terminal)
# Terminal 1 - General monitoring
while true; do 
  clear
  echo "$(date): Apache VPA Monitoring"
  echo "=== VPA STATUS ==="
  kubectl get vpa -n apache
  echo
  echo "=== PODS ==="
  kubectl get pods -n apache | grep apache-deployment
  echo
  echo "=== RESOURCE USAGE ==="
  kubectl top pods -n apache 2>/dev/null || echo "Metrics loading..."
  echo "========================="
  sleep 8
done

#################################################################################################################################

# Generate Load Test
# Start the load test pod
kubectl apply -f apache-benchmark.yaml

# Generate external load if benchmark pod isn't working
for i in {1..500}; do 
  curl -s http://localhost:80/ > /dev/null &
  if [ $((i % 100)) -eq 0 ]; then
    echo "Sent $i requests"
    sleep 2
  fi
done

#################################################################################################################################

# Observe Scaling Behavior
# Check scaling events
kubectl describe vpa apache-vpa -n apache

# Check deployment events
kubectl describe deployment apache-deployment -n apache

# View all events
kubectl get events -n apache --sort-by='.lastTimestamp'

# Final status check
kubectl get vpa,pods,svc -n apache

#################################################################################################################################

# Cleanup
# Delete just the namespace
kubectl delete namespace apache

# Delete the entire cluster
kind delete cluster --name=apache-test

#################################################################################################################################