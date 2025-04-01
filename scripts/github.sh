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
ECR_POLICY_NAME="ecr-direct-access-$GITHUB_REPO-policy"

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

# Create a standalone ECR policy with specific focus on GetAuthorizationToken
echo "Creating dedicated ECR access policy..."
cat > ecr-direct-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
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

# Create or update a policy
create_or_update_policy() {
  local policy_name=$1
  local policy_document=$2
  
  # Check if policy exists
  if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" &> /dev/null; then
    echo "Policy ${policy_name} already exists, updating..."
    
    # Get the current version
    POLICY_VERSION=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --query "Versions[?IsDefaultVersion==\`true\`].VersionId" --output text)
    
    # Delete oldest policy version if we have 5 versions (the maximum)
    VERSIONS_COUNT=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --query "length(Versions)" --output text)
    if [ $VERSIONS_COUNT -ge 5 ]; then
      OLDEST_VERSION=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --query "Versions[-1].VersionId" --output text)
      aws iam delete-policy-version --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" --version-id $OLDEST_VERSION
    fi
    
    # Create new version (and set as default)
    aws iam create-policy-version \
      --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" \
      --policy-document file://${policy_document} \
      --set-as-default
    
    POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"
  else
    echo "Creating new policy ${policy_name}..."
    POLICY_ARN=$(aws iam create-policy --policy-name $policy_name --policy-document file://${policy_document} --query "Policy.Arn" --output text)
  fi
  
  echo $POLICY_ARN
}

# Create or update the ECR policy
ECR_POLICY_ARN=$(create_or_update_policy $ECR_POLICY_NAME "ecr-direct-access-policy.json")
echo "ECR access policy created/updated: $ECR_POLICY_ARN"

# Check if role exists
ROLE_EXISTS=false
if aws iam get-role --role-name $ROLE_NAME &> /dev/null; then
    ROLE_EXISTS=true
    echo "Role $ROLE_NAME already exists"
else
    echo "Role $ROLE_NAME does not exist, will create it"
fi

# Create the trust policy for GitHub OIDC provider
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
if [ "$ROLE_EXISTS" = true ]; then
    echo "Updating existing role trust policy..."
    aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://trust-policy.json
else
    echo "Creating new IAM role..."
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json
fi

# Attach ECR policy to the role
echo "Attaching ECR policy to role..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn $ECR_POLICY_ARN

# Attach AWS managed ECR policies
echo "Attaching AWS managed ECR policies..."
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn "arn:aws:iam::aws:policy/AmazonECR-FullAccess"
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn "arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicFullAccess"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo "IAM role updated: $ROLE_ARN"

# Add the role to the EKS cluster auth configmap
read -p "Do you want to add this role to the EKS cluster's aws-auth ConfigMap? (y/n): " ADD_TO_EKS
if [[ "$ADD_TO_EKS" == "y" || "$ADD_TO_EKS" == "Y" ]]; then
    read -p "Enter your EKS cluster name: " EKS_CLUSTER_NAME
    
    # Update kubeconfig first
    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
    
    # Check if eksctl is installed
    if command -v eksctl &> /dev/null; then
        # Use eksctl to add IAM role to EKS cluster (this is idempotent)
        echo "Adding role to EKS cluster auth using eksctl..."
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
rm -f ecr-direct-access-policy.json trust-policy.json

echo "Setup complete! The following policies have been attached to your role:"
echo "- Custom ECR access policy: $ECR_POLICY_ARN"
echo "- AWS managed ECR policies: AmazonECR-FullAccess, AmazonElasticContainerRegistryPublicFullAccess"
echo ""
echo "Add the following secrets to your GitHub repository:"
echo "AWS_ROLE_ARN: $ROLE_ARN"
echo "AWS_REGION: <your-aws-region>"
echo "EKS_CLUSTER_NAME: <your-eks-cluster-name>"