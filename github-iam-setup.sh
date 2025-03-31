#!/bin/bash
# github-iam-setup.sh - Script to create an IAM role for GitHub Actions

set -e

# Check for required parameters
if [ $# -lt 2 ]; then
  echo "Usage: $0 <github-org> <github-repo>"
  echo "Example: $0 npolovina talk2me"
  exit 1
fi

GITHUB_ORG=$1
GITHUB_REPO=$2
ROLE_NAME="github-actions-$GITHUB_REPO-role"
POLICY_NAME="github-actions-$GITHUB_REPO-policy"

# Check for AWS CLI
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "ERROR: AWS credentials not configured properly."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Create the IAM policy document
echo "Creating IAM policy for GitHub Actions..."
cat > github-actions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:GetAuthorizationToken"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "eks:AccessKubernetesApi"
            ],
            "Resource": "arn:aws:eks:*:${ACCOUNT_ID}:cluster/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the IAM policy
POLICY_ARN=$(aws iam create-policy --policy-name $POLICY_NAME --policy-document file://github-actions-policy.json --query "Policy.Arn" --output text)
echo "IAM Policy created: $POLICY_ARN"

# Create the trust policy for GitHub OIDC
cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
                }
            }
        }
    ]
}
EOF

# Check if OIDC provider exists
OIDC_PROVIDER_EXISTS=$(aws iam list-open-id-connect-providers | grep "token.actions.githubusercontent.com" || true)
if [ -z "$OIDC_PROVIDER_EXISTS" ]; then
    echo "Creating GitHub Actions OIDC provider..."
    aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
    echo "OIDC provider created."
else
    echo "GitHub Actions OIDC provider already exists."
fi

# Create the IAM role
echo "Creating IAM role for GitHub Actions..."
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN

# Now create an EKS specific policy for kubectl access
echo "Creating EKS access policy..."
cat > eks-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

EKS_POLICY_NAME="eks-access-$GITHUB_REPO-policy"
EKS_POLICY_ARN=$(aws iam create-policy --policy-name $EKS_POLICY_NAME --policy-document file://eks-access-policy.json --query "Policy.Arn" --output text)
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $EKS_POLICY_ARN
echo "EKS access policy created and attached: $EKS_POLICY_ARN"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "IAM role created: $ROLE_ARN"

# Add the role to the EKS cluster auth configmap
read -p "Do you want to add this role to the EKS cluster's aws-auth ConfigMap? (y/n): " ADD_TO_EKS
if [[ "$ADD_TO_EKS" == "y" || "$ADD_TO_EKS" == "Y" ]]; then
    read -p "Enter your EKS cluster name: " EKS_CLUSTER_NAME
    
    # Get the current aws-auth ConfigMap
    echo "Updating EKS aws-auth ConfigMap..."
    
    # Update kubeconfig first
    aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
    
    # Check if eksctl is installed
    if command -v eksctl &> /dev/null; then
        # Use eksctl to add IAM role to EKS cluster
        eksctl create iamidentitymapping \
            --cluster $EKS_CLUSTER_NAME \
            --arn $ROLE_ARN \
            --username github-actions \
            --group system:masters
        
        echo "Role added to EKS cluster auth."
    else
        echo "eksctl not found. Please install eksctl and run:"
        echo "eksctl create iamidentitymapping --cluster $EKS_CLUSTER_NAME --arn $ROLE_ARN --username github-actions --group system:masters"
    fi
fi

# Clean up
rm -f github-actions-policy.json trust-policy.json eks-access-policy.json

echo "Setup complete! Add the following secrets to your GitHub repository:"
echo "AWS_ROLE_ARN: $ROLE_ARN"
echo "AWS_REGION: <your-aws-region>"
echo "EKS_CLUSTER_NAME: <your-eks-cluster-name>"