#!/bin/zsh

# For AMD64 / x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-$(uname)-amd64
# For ARM64
[ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-$(uname)-arm64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
export CTLPTL_VERSION="0.8.25"
sudo curl -fsSL https://github.com/tilt-dev/ctlptl/releases/download/v$CTLPTL_VERSION/ctlptl.$CTLPTL_VERSION.linux.x86_64.tar.gz | sudo tar -xzv -C /usr/local/bin ctlptl
sudo curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash

export CLUSTER_NAME="kind"

# Check if the cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "Deleting existing cluster $CLUSTER_NAME"
    kind delete cluster --name $CLUSTER_NAME
fi

# Step 1: Create a kube cluster using kind emulator with a local registry
kind create cluster --name $CLUSTER_NAME --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 32000
    hostPort: 32000
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:32000"]
    endpoint = ["http://localhost:32000"]
EOF

mkdir $HOME/certs
sudo usermod -aG docker $USER
sudo apt-get install openssl

IP_ADDRESS=$(hostname -I | awk '{print $1}') openssl req \
    -new \
    -newkey rsa:4096 \
    -days 365 \
    -nodes \
    -x509 \
    -subj "/C=GE/ST=BD/L=Stuttgart/O=MyOrg/CN=mytest.com" \
    -reqexts req_ext \
    -extensions req_ext \
    -config openssl.cnf \
    -keyout $HOME/certs/test.key \
    -out $HOME/certs/test.cert


DOCKER_HOST_IP=$(hostname -I | awk '{print $1}')

docker run -d -p 5000:5000 --restart=always --name registry \
-e REGISTRY_HTTP_TLS_CERTIFICATE=$HOME/certs/test.cert \
-e REGISTRY_HTTP_TLS_KEY=$HOME/certs/test.key \
-v $HOME/certs:$HOME/certs \
registry:latest

docker start registry
docker build -t test:v1 .
docker tag test:v1 $DOCKER_HOST_IP:5000/test:v1
docker push $DOCKER_HOST_IP:5000/test:v1
docker image rm test:v1

# Step 1: Deployment should be a custom nginx container running on port 8081
cat <<EOF > nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: "${DOCKER_HOST_IP}:5000/test:v1"
        ports:
        - containerPort: 8081
EOF

# Step 2: Service should also be running on port 8081
cat <<EOF > nginx-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  type: NodePort
  ports:
    - protocol: TCP
      port: 8081
      targetPort: 8081
EOF

# Step 3: Using tilt, deploy kube deployment/service to the kind cluster
cat <<EOF > Tiltfile
local('docker build -t my-custom-nginx .')
k8s_yaml('nginx-deployment.yaml')
k8s_yaml('nginx-service.yaml')
EOF


# Check the overall script status
overall_status=$?

# Print the overall script status
echo "Overall Script Exit Status: $overall_status"

tilt up

