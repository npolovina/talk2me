#!/bin/bash
# create-permissive-github-role.sh - Create highly permissive IAM role for GitHub Actions

set -e

# Configuration
ROLE_NAME="talk2me-role"
GITHUB_ORG="npolovina"
GITHUB_REPO="talk2me"
EKS_CLUSTER_NAME="talk2me"
AWS_REGION="us-east-1"

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Creating permissive IAM role for GitHub Actions...${NC}"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo -e "${GREEN}Using AWS Account: ${AWS_ACCOUNT_ID}${NC}"

# Create a very permissive policy document
cat > permissive-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ECRFullAccess",
            "Effect": "Allow",
            "Action": "ecr:*",
            "Resource": "*"
        },
        {
            "Sid": "EKSFullAccess",
            "Effect": "Allow",
            "Action": "eks:*",
            "Resource": "*"
        },
        {
            "Sid": "EC2NetworkAccess",
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeRouteTables",
                "ec2:DescribeInternetGateways",
                "ec2:DescribeNatGateways",
                "ec2:DescribeAddresses",
                "ec2:DescribeNetworkInterfaces"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ELBFullAccess",
            "Effect": "Allow",
            "Action": "elasticloadbalancing:*",
            "Resource": "*"
        },
        {
            "Sid": "IAMPassRole",
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "*"
        },
        {
            "Sid": "Route53Access",
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
            "Sid": "ACMAccess",
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
            "Sid": "SecretsManagerAccess",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "*"
        },
        {
            "Sid": "CloudWatchAccess",
            "Effect": "Allow",
            "Action": [
                "logs:*",
                "cloudwatch:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create trust policy for GitHub Actions
cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
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

# Check if OIDC provider exists, create if not
GITHUB_OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers | jq -r '.OpenIDConnectProviderList[] | select(.Arn | contains("token.actions.githubusercontent.com")) | .Arn')

if [ -z "$GITHUB_OIDC_PROVIDER_ARN" ]; then
    echo -e "${YELLOW}GitHub OIDC provider not found. Creating new provider...${NC}"
    
    # GitHub's OIDC provider thumbprint
    THUMBPRINT="6938fd4d98bab03faadb97b34396831e3780aea1"
    
    GITHUB_OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
        --url "https://token.actions.githubusercontent.com" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "$THUMBPRINT" \
        --query "OpenIDConnectProviderArn" --output text)
        
    echo -e "${GREEN}Created GitHub OIDC provider: ${GITHUB_OIDC_PROVIDER_ARN}${NC}"
else
    echo -e "${GREEN}GitHub OIDC provider already exists: ${GITHUB_OIDC_PROVIDER_ARN}${NC}"
fi

# Delete the role if it exists (clean slate approach)
if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    echo -e "${YELLOW}Role already exists. Deleting and recreating it...${NC}"
    
    # Detach all policies
    for POLICY_ARN in $(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --query "AttachedPolicies[*].PolicyArn" --output text); do
        echo -e "${YELLOW}Detaching policy: ${POLICY_ARN}${NC}"
        aws iam detach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"
    done
    
    # Delete the role
    aws iam delete-role --role-name "${ROLE_NAME}"
    echo -e "${GREEN}Role deleted.${NC}"
    
    # Wait a moment for AWS to process the deletion
    sleep 5
fi

# Create the IAM role
echo -e "${YELLOW}Creating new IAM role: ${ROLE_NAME}${NC}"
aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file://trust-policy.json \
    --description "Permissive role for GitHub Actions"

# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query "Role.Arn" --output text)
echo -e "${GREEN}Created role: ${ROLE_ARN}${NC}"

# Create the policy
POLICY_NAME="${ROLE_NAME}-policy"
echo -e "${YELLOW}Creating policy: ${POLICY_NAME}${NC}"

# Check if the policy already exists
if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" &>/dev/null; then
    echo -e "${YELLOW}Policy already exists. Deleting and recreating it...${NC}"
    
    # List all versions
    for VERSION_ID in $(aws iam list-policy-versions --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text); do
        echo -e "${YELLOW}Deleting policy version: ${VERSION_ID}${NC}"
        aws iam delete-policy-version --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" --version-id "${VERSION_ID}"
    done
    
    # Delete the policy
    aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Wait a moment for AWS to process the deletion
    sleep 5
fi

# Create the policy
POLICY_ARN=$(aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://permissive-policy.json \
    --description "Permissive policy for GitHub Actions" \
    --query "Policy.Arn" --output text)

echo -e "${GREEN}Created policy: ${POLICY_ARN}${NC}"

# Attach the policy to the role
echo -e "${YELLOW}Attaching policy to role...${NC}"
aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY_ARN}"
echo -e "${GREEN}Attached policy to role.${NC}"

# Also attach key AWS managed policies
echo -e "${YELLOW}Attaching AWS managed policies...${NC}"
MANAGED_POLICIES=(
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    "arn:aws:iam::aws:policy/AmazonECR-FullAccess"
)

for POLICY in "${MANAGED_POLICIES[@]}"; do
    echo -e "${YELLOW}Attaching: ${POLICY}${NC}"
    if aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${POLICY}" 2>/dev/null; then
        echo -e "${GREEN}Attached: ${POLICY}${NC}"
    else
        echo -e "${RED}Failed to attach: ${POLICY} (policy may not exist)${NC}"
    fi
done

# Update the EKS cluster aws-auth ConfigMap
echo -e "${YELLOW}Updating EKS cluster aws-auth ConfigMap...${NC}"

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig for EKS cluster...${NC}"
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"

# Check if eksctl is installed
if ! command -v eksctl &>/dev/null; then
    echo -e "${RED}eksctl not found. Installing...${NC}"
    
    # Install eksctl
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    else
        curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | tar xz -C /tmp
    fi
    
    sudo mv /tmp/eksctl /usr/local/bin
    
    if ! command -v eksctl &>/dev/null; then
        echo -e "${RED}Failed to install eksctl. You'll need to manually update aws-auth ConfigMap.${NC}"
        echo -e "${YELLOW}Add this to your aws-auth ConfigMap:${NC}"
        echo "mapRoles:"
        echo "  - rolearn: ${ROLE_ARN}"
        echo "    username: github-actions"
        echo "    groups:"
        echo "      - system:masters"
        exit 1
    fi
fi

# First try to remove any existing entry to avoid conflicts
eksctl delete iamidentitymapping \
    --cluster "${EKS_CLUSTER_NAME}" \
    --arn "${ROLE_ARN}" \
    --region "${AWS_REGION}" || true  # Don't fail if identity doesn't exist

# Add the role to aws-auth ConfigMap
echo -e "${YELLOW}Adding role to aws-auth ConfigMap...${NC}"
eksctl create iamidentitymapping \
    --cluster "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --arn "${ROLE_ARN}" \
    --username "github-actions" \
    --group "system:masters"

echo -e "${GREEN}Role added to aws-auth ConfigMap.${NC}"

# Create namespace if it doesn't exist
echo -e "${YELLOW}Creating talk2me namespace if it doesn't exist...${NC}"
kubectl create namespace talk2me --dry-run=client -o yaml | kubectl apply -f -

# Clean up files
rm -f permissive-policy.json trust-policy.json

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}Permissive IAM role setup completed successfully!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "${YELLOW}Role ARN: ${ROLE_ARN}${NC}"
echo -e "${YELLOW}"
echo "Add these secrets to your GitHub repository:"
echo "AWS_ROLE_ARN: ${ROLE_ARN}"
echo "AWS_REGION: ${AWS_REGION}"
echo "EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}"
echo -e "${NC}"
echo -e "${RED}WARNING: This role has very permissive access. Consider restricting permissions after your deployment is working.${NC}"