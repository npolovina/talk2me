#!/bin/bash
# github-iam-setup.sh - Script to create or update an IAM role for GitHub Actions

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
EKS_POLICY_NAME="eks-access-$GITHUB_REPO-policy"
ECR_POLICY_NAME="ecr-access-$GITHUB_REPO-policy"

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

# Create a separate ECR policy document with full ECR access
cat > ecr-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:BatchGetImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the IAM policy document for GitHub Actions
cat > github-actions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
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

# Create EKS access policy
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

# Function to create or update a policy
create_or_update_policy() {
  local policy_name=$1
  local policy_document=$2
  
  # Check if policy exists
  if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" &> /dev/null; then
    echo "Policy ${policy_name} already exists, updating..."
    
    # Get the current version
    POLICY_VERSION=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --query "Versions[?IsDefaultVersion==\`true\`].VersionId" --output text)
    
    # Create new version (and set as default)
    aws iam create-policy-version \
      --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" \
      --policy-document file://${policy_document} \
      --set-as-default
      
    # Delete oldest policy version if we have 5 versions (the maximum)
    VERSIONS_COUNT=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --query "length(Versions)" --output text)
    if [ $VERSIONS_COUNT -ge 5 ]; then
      OLDEST_VERSION=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --query "Versions[-1].VersionId" --output text)
      aws iam delete-policy-version --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --version-id $OLDEST_VERSION
    fi
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
  else
    echo "Creating new policy ${policy_name}..."
    POLICY_ARN=$(aws iam create-policy --policy-name $policy_name --policy-document file://${policy_document} --query "Policy.Arn" --output text)
  fi
  
  echo $POLICY_ARN
}

# Create or update the policies
GITHUB_POLICY_ARN=$(create_or_update_policy $POLICY_NAME "github-actions-policy.json")
echo "GitHub Actions policy updated: $GITHUB_POLICY_ARN"

EKS_POLICY_ARN=$(create_or_update_policy $EKS_POLICY_NAME "eks-access-policy.json")
echo "EKS access policy updated: $EKS_POLICY_ARN"

ECR_POLICY_ARN=$(create_or_update_policy $ECR_POLICY_NAME "ecr-access-policy.json")
echo "ECR access policy updated: $ECR_POLICY_ARN"

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

# Create or update the IAM role
if aws iam get-role --role-name $ROLE_NAME &> /dev/null; then
    echo "Role $ROLE_NAME already exists, updating trust policy..."
    aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://trust-policy.json
else
    echo "Creating IAM role for GitHub Actions..."
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json
fi

# Attach policies to role (will update if already attached)
echo "Attaching policies to role..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $GITHUB_POLICY_ARN
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $EKS_POLICY_ARN
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $ECR_POLICY_ARN

# Also attach the AWS managed ECR power user policy for good measure
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn "arn:aws:iam::aws:policy/AmazonECR-FullAccess"
echo "Attached AWS managed ECR policy for additional permissions"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "IAM role updated: $ROLE_ARN"

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
        # Use eksctl to add IAM role to EKS cluster (this is idempotent)
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
rm -f github-actions-policy.json trust-policy.json eks-access-policy.json ecr-access-policy.json

echo "Setup complete! Add the following secrets to your GitHub repository:"
echo "AWS_ROLE_ARN: $ROLE_ARN"
echo "AWS_REGION: <your-aws-region>"
echo "EKS_CLUSTER_NAME: <your-eks-cluster-name>"