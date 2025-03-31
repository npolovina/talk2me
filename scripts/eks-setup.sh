#!/bin/bash
# eks-setup.sh - Script to create an EKS cluster for Talk2Me application

set -e

# Configuration variables
CLUSTER_NAME="talk2me"
REGION="us-east-1"
NODE_TYPE="t3.medium"
NODE_MIN=2
NODE_MAX=4
NODE_DESIRED=2

# Check for AWS CLI
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check for eksctl
if ! command -v eksctl &> /dev/null; then
    echo "ERROR: eksctl is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "ERROR: AWS credentials not configured properly."
    exit 1
fi

echo "Creating EKS cluster: $CLUSTER_NAME in region $REGION"
echo "This will take approximately 15-20 minutes..."

# Create the EKS cluster using eksctl
eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --node-type "$NODE_TYPE" \
    --nodes-min "$NODE_MIN" \
    --nodes-max "$NODE_MAX" \
    --nodes "$NODE_DESIRED" \
    --with-oidc \
    --managed \
    --alb-ingress-access

# Check if the cluster was created successfully
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create EKS cluster."
    exit 1
fi

echo "EKS cluster created successfully!"

# Install AWS Load Balancer Controller
echo "Installing AWS Load Balancer Controller..."

# Create IAM policy for the AWS Load Balancer Controller
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
    echo "Creating IAM policy for AWS Load Balancer Controller..."
    curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
    
    POLICY_ARN=$(aws iam create-policy \
        --policy-name $POLICY_NAME \
        --policy-document file://iam-policy.json \
        --query 'Policy.Arn' --output text)
        
    rm iam-policy.json
else
    echo "IAM policy $POLICY_NAME already exists."
fi

# Create service account for the AWS Load Balancer Controller
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=$POLICY_ARN \
    --override-existing-serviceaccounts \
    --approve

# Install AWS Load Balancer Controller using Helm
echo "Installing AWS Load Balancer Controller using Helm..."

# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller

# Create ECR repositories
echo "Creating ECR repositories for Talk2Me..."

aws ecr create-repository --repository-name talk2me-frontend --image-scanning-configuration scanOnPush=true || echo "Frontend repository already exists"
aws ecr create-repository --repository-name talk2me-backend --image-scanning-configuration scanOnPush=true || echo "Backend repository already exists"

# Create Kubernetes namespace
echo "Creating Talk2Me namespace in Kubernetes..."
kubectl create namespace talk2me --dry-run=client -o yaml | kubectl apply -f -

echo "EKS setup complete! You can now deploy the Talk2Me application using the GitHub Actions workflows."
echo ""
echo "Don't forget to add the following secrets to your GitHub repository:"
echo "- AWS_ROLE_ARN: IAM role ARN with permissions to push to ECR and deploy to EKS"
echo "- AWS_REGION: $REGION"
echo "- ECR_FRONTEND_REPO: talk2me-frontend"
echo "- ECR_BACKEND_REPO: talk2me-backend"
echo "- EKS_CLUSTER_NAME: $CLUSTER_NAME"
echo "- DEEPSEEK_API_KEY: Your DeepSeek API key"