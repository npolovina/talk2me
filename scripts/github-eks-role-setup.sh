#!/bin/bash
# setup-github-eks-role.sh - Comprehensive IAM role setup for GitHub Actions to access EKS

set -e

# Text colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration - Update these variables as needed
GITHUB_ORG="npolovina"
GITHUB_REPO="talk2me"
ROLE_NAME="github-actions-talk2me-role"
EKS_CLUSTER_NAME="talk2me"
AWS_REGION="us-east-1"

# Print banner
echo -e "${GREEN}"
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃                 GitHub Actions EKS Role Setup                      ┃"
echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
echo -e "${NC}"

# Check for AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured properly.${NC}"
    exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}AWS Account ID: ${ACCOUNT_ID}${NC}"

echo -e "${YELLOW}Creating comprehensive IAM role for GitHub Actions...${NC}"

# Create the trust policy file for GitHub OIDC
echo -e "${YELLOW}Creating trust policy for GitHub OIDC provider...${NC}"
cat > github-trust-policy.json << EOF
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

# Create the permissions policy file with comprehensive permissions
echo -e "${YELLOW}Creating permissions policy for GitHub Actions...${NC}"
cat > github-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:UpdateClusterConfig",
                "eks:DescribeUpdate",
                "eks:AccessKubernetesApi"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken"
            ],
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
                "ecr:PutImage",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:CreateRepository",
                "ecr:TagResource"
            ],
            "Resource": "arn:aws:ecr:*:${ACCOUNT_ID}:repository/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "iam:ListRoles",
                "iam:PassRole"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:GetHostedZone",
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "acm:ListCertificates",
                "acm:DescribeCertificate",
                "acm:RequestCertificate",
                "acm:AddTagsToCertificate"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeLoadBalancerAttributes",
                "elasticloadbalancing:DescribeListeners",
                "elasticloadbalancing:DescribeListenerCertificates",
                "elasticloadbalancing:DescribeSSLPolicies",
                "elasticloadbalancing:DescribeRules",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetGroupAttributes",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DescribeTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeAddresses",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeRouteTables"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Check if OIDC provider exists
echo -e "${YELLOW}Checking if GitHub OIDC provider exists...${NC}"
OIDC_PROVIDER_EXISTS=$(aws iam list-open-id-connect-providers | grep "token.actions.githubusercontent.com" || true)

if [ -z "$OIDC_PROVIDER_EXISTS" ]; then
    echo -e "${YELLOW}Creating GitHub Actions OIDC provider...${NC}"
    aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
    echo -e "${GREEN}GitHub OIDC provider created.${NC}"
else
    echo -e "${GREEN}GitHub OIDC provider already exists.${NC}"
fi

# Check if role already exists
ROLE_EXISTS=false
if aws iam get-role --role-name $ROLE_NAME &> /dev/null; then
    ROLE_EXISTS=true
    echo -e "${YELLOW}Role ${ROLE_NAME} already exists, updating...${NC}"
else
    echo -e "${YELLOW}Creating new role ${ROLE_NAME}...${NC}"
fi

# Create or update the IAM role
if [ "$ROLE_EXISTS" = true ]; then
    # Update trust policy of existing role
    aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://github-trust-policy.json
else
    # Create new role
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://github-trust-policy.json
fi

# Create or update inline policy
echo -e "${YELLOW}Attaching permissions policy to role...${NC}"
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name "${ROLE_NAME}-permissions" \
    --policy-document file://github-permissions-policy.json

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"

# Update EKS cluster to allow the role to access the Kubernetes API server
echo -e "${YELLOW}Updating EKS cluster to allow the role to access Kubernetes...${NC}"

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig for EKS cluster ${EKS_CLUSTER_NAME}...${NC}"
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

# Check if eksctl is installed
if ! command -v eksctl &> /dev/null; then
    echo -e "${YELLOW}Installing eksctl...${NC}"
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl /usr/local/bin
    
    if ! command -v eksctl &> /dev/null; then
        echo -e "${RED}Error: Failed to install eksctl. Please install it manually.${NC}"
        echo -e "${RED}See: https://eksctl.io/installation/${NC}"
        exit 1
    fi
fi

# Add IAM role to EKS cluster's aws-auth ConfigMap to grant it permission to manage the cluster
echo -e "${YELLOW}Adding role to EKS cluster's aws-auth ConfigMap...${NC}"
eksctl create iamidentitymapping \
    --cluster $EKS_CLUSTER_NAME \
    --region $AWS_REGION \
    --arn $ROLE_ARN \
    --username github-actions-role \
    --group system:masters

# Verify the update
echo -e "${YELLOW}Verifying aws-auth ConfigMap...${NC}"
kubectl describe configmap -n kube-system aws-auth

# Clean up temporary files
rm -f github-trust-policy.json github-permissions-policy.json

echo -e "${GREEN}"
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃                      Setup Complete!                               ┃"
echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
echo -e "${NC}"

echo -e "${YELLOW}GitHub Actions Role ARN: ${ROLE_ARN}${NC}"
echo
echo -e "${YELLOW}Add the following secrets to your GitHub repository:${NC}"
echo -e "AWS_ROLE_ARN: ${ROLE_ARN}"
echo -e "AWS_REGION: ${AWS_REGION}"
echo -e "EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}"