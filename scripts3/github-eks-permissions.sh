#!/bin/bash
# github-eks-permissions.sh - Comprehensive script to set up GitHub Actions permissions for EKS
# Run this after eks-setup.sh to properly configure IAM roles and permissions

set -e

# Configuration
GITHUB_ORG="npolovina"
GITHUB_REPO="talk2me"
ROLE_NAME="github-actions-$GITHUB_REPO-role"
EKS_CLUSTER_NAME="talk2me"
AWS_REGION="us-east-1"

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting comprehensive GitHub Actions EKS permission setup...${NC}"

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo -e "${GREEN}Using AWS Account: ${AWS_ACCOUNT_ID}${NC}"

# Verify EKS cluster exists
echo -e "${YELLOW}Verifying EKS cluster exists...${NC}"
if aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} > /dev/null 2>&1; then
    echo -e "${GREEN}EKS cluster '${EKS_CLUSTER_NAME}' found.${NC}"
else
    echo -e "${RED}EKS cluster '${EKS_CLUSTER_NAME}' not found. Please run eks-setup.sh first.${NC}"
    exit 1
fi

# Check if OIDC provider exists, create if not
echo -e "${YELLOW}Setting up GitHub OIDC provider...${NC}"
GITHUB_OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers | jq -r '.OpenIDConnectProviderList[] | select(.Arn | contains("token.actions.githubusercontent.com")) | .Arn')

if [ -z "$GITHUB_OIDC_PROVIDER_ARN" ]; then
    echo -e "${YELLOW}GitHub OIDC provider not found. Creating new provider...${NC}"
    
    # GitHub's OIDC provider thumbprint (current as of April 2025)
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

# Create policy documents
echo -e "${YELLOW}Creating IAM policies...${NC}"

# ECR Policy
cat > ecr-policy.json << EOF
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
                "ecr:PutImage",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImages",
                "ecr:CreateRepository",
                "ecr:TagResource"
            ],
            "Resource": "arn:aws:ecr:*:${AWS_ACCOUNT_ID}:repository/*"
        }
    ]
}
EOF

# EKS Policy
cat > eks-policy.json << EOF
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
                "eks:AccessKubernetesApi",
                "eks:UpdateClusterConfig",
                "eks:DescribeUpdate"
            ],
            "Resource": "arn:aws:eks:*:${AWS_ACCOUNT_ID}:cluster/*"
        }
    ]
}
EOF

# Kubernetes API Policy
cat > k8s-api-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:ListFargateProfiles",
                "eks:DescribeFargateProfile",
                "eks:ListNodegroups",
                "eks:DescribeNodegroup",
                "eks:ListUpdates",
                "eks:DescribeUpdate",
                "eks:AccessKubernetesApi"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# ALB Policy
cat > alb-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
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
                "elasticloadbalancing:CreateLoadBalancer",
                "elasticloadbalancing:CreateListener",
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:CreateTargetGroup",
                "elasticloadbalancing:ModifyLoadBalancerAttributes",
                "elasticloadbalancing:ModifyListener",
                "elasticloadbalancing:ModifyRule",
                "elasticloadbalancing:ModifyTargetGroupAttributes",
                "elasticloadbalancing:SetIpAddressType",
                "elasticloadbalancing:SetSubnets",
                "elasticloadbalancing:SetSecurityGroups",
                "elasticloadbalancing:SetRulePriorities",
                "elasticloadbalancing:AddTags",
                "elasticloadbalancing:RemoveTags",
                "elasticloadbalancing:RegisterTargets",
                "elasticloadbalancing:DeregisterTargets",
                "elasticloadbalancing:AddListenerCertificates",
                "elasticloadbalancing:RemoveListenerCertificates",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:DeleteListener",
                "elasticloadbalancing:DeleteRule",
                "elasticloadbalancing:DeleteTargetGroup"
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

# Create DNS Policy
cat > dns-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListHostedZones",
                "route53:GetHostedZone",
                "route53:ListResourceRecordSets",
                "route53:ListTagsForResource"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/*"
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
                "acm:DeleteCertificate"
            ],
            "Resource": "arn:aws:acm:*:${AWS_ACCOUNT_ID}:certificate/*"
        }
    ]
}
EOF

# Function to create or update policy
create_or_update_policy() {
    local policy_name=$1
    local description=$2
    local policy_file=$3
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" &> /dev/null; then
        echo -e "${YELLOW}Policy ${policy_name} already exists. Updating...${NC}"
        
        # Get the versions
        VERSIONS=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
        
        # If we have 4 or more non-default versions, delete the oldest to make room
        if [ "$(echo $VERSIONS | wc -w)" -ge 4 ]; then
            OLDEST_VERSION=$(aws iam list-policy-versions --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" --query 'Versions[-1].VersionId' --output text)
            aws iam delete-policy-version --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" --version-id "$OLDEST_VERSION"
            echo -e "${YELLOW}Deleted oldest policy version: ${OLDEST_VERSION}${NC}"
        fi
        
        # Create new version
        aws iam create-policy-version \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}" \
            --policy-document file://${policy_file} \
            --set-as-default > /dev/null
            
        echo -e "${GREEN}Updated policy: ${policy_name}${NC}"
        POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    else
        echo -e "${YELLOW}Creating new policy: ${policy_name}${NC}"
        POLICY_ARN=$(aws iam create-policy \
            --policy-name "${policy_name}" \
            --description "${description}" \
            --policy-document file://${policy_file} \
            --query 'Policy.Arn' --output text)
        echo -e "${GREEN}Created policy: ${POLICY_ARN}${NC}"
    fi
    
    echo "${POLICY_ARN}"
}

# Create the policies
echo -e "${YELLOW}Verifying policy ARNs...${NC}"
ECR_POLICY_ARN=$(create_or_update_policy "github-actions-${GITHUB_REPO}-ecr-policy" "ECR access for GitHub Actions" "ecr-policy.json")
echo -e "${YELLOW}ECR Policy ARN: ${ECR_POLICY_ARN}${NC}"

EKS_POLICY_ARN=$(create_or_update_policy "github-actions-${GITHUB_REPO}-eks-policy" "EKS access for GitHub Actions" "eks-policy.json")
echo -e "${YELLOW}EKS Policy ARN: ${EKS_POLICY_ARN}${NC}"

K8S_POLICY_ARN=$(create_or_update_policy "github-actions-${GITHUB_REPO}-k8s-api-policy" "Kubernetes API access for GitHub Actions" "k8s-api-policy.json")
echo -e "${YELLOW}K8s API Policy ARN: ${K8S_POLICY_ARN}${NC}"

ALB_POLICY_ARN=$(create_or_update_policy "github-actions-${GITHUB_REPO}-alb-policy" "ALB and network access for GitHub Actions" "alb-policy.json")
echo -e "${YELLOW}ALB Policy ARN: ${ALB_POLICY_ARN}${NC}"

DNS_POLICY_ARN=$(create_or_update_policy "github-actions-${GITHUB_REPO}-dns-policy" "DNS and Route53 access for GitHub Actions" "dns-policy.json")
echo -e "${YELLOW}DNS Policy ARN: ${DNS_POLICY_ARN}${NC}"

# Create trust policy for the role
cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "${GITHUB_OIDC_PROVIDER_ARN}"
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

# Check if role exists
echo -e "${YELLOW}Setting up IAM role with OIDC trust relationship...${NC}"
if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
    echo -e "${YELLOW}Updating existing IAM role: ${ROLE_NAME}${NC}"
    aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document file://trust-policy.json
else
    echo -e "${YELLOW}Creating new IAM role: ${ROLE_NAME}${NC}"
    aws iam create-role --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for GitHub Actions to access AWS resources" > /dev/null
fi

ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query "Role.Arn" --output text)
echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"

# Function to attach policy to role
attach_policy() {
    local role_name=$1
    local policy_arn=$2
    local policy_name=$(basename $policy_arn)
    
    echo -e "${YELLOW}Attaching policy: ${policy_name}${NC}"
    
    # Check if policy is already attached
    if aws iam list-attached-role-policies --role-name "${role_name}" | grep -q "${policy_arn}"; then
        echo -e "${GREEN}Policy already attached: ${policy_name}${NC}"
    else
        if aws iam attach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}"; then
            echo -e "${GREEN}Successfully attached policy: ${policy_name}${NC}"
        else
            echo -e "${RED}Failed to attach policy: ${policy_name}${NC}"
        fi
    fi
}

# Attach policies to the role
echo -e "${YELLOW}Attaching policies to the role...${NC}"
attach_policy "${ROLE_NAME}" "${ECR_POLICY_ARN}"
attach_policy "${ROLE_NAME}" "${EKS_POLICY_ARN}"
attach_policy "${ROLE_NAME}" "${K8S_POLICY_ARN}"
attach_policy "${ROLE_NAME}" "${ALB_POLICY_ARN}"
attach_policy "${ROLE_NAME}" "${DNS_POLICY_ARN}"

# Also try to attach AWS managed policies
echo -e "${YELLOW}Attaching AWS managed policies...${NC}"
AWS_MANAGED_POLICIES=(
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    "arn:aws:iam::aws:policy/AmazonECR-FullAccess"
)

for policy_arn in "${AWS_MANAGED_POLICIES[@]}"; do
    policy_name=$(echo $policy_arn | awk -F/ '{print $2}')
    echo -e "${YELLOW}Attaching AWS managed policy: ${policy_name}${NC}"
    
    if aws iam list-attached-role-policies --role-name "${ROLE_NAME}" | grep -q "${policy_arn}"; then
        echo -e "${GREEN}Policy already attached: ${policy_name}${NC}"
    else
        if aws iam attach-role-policy --role-name "${ROLE_NAME}" --policy-arn "${policy_arn}" 2>/dev/null; then
            echo -e "${GREEN}Successfully attached policy: ${policy_name}${NC}"
        else
            echo -e "${RED}Failed to attach policy: ${policy_name}. Policy may not exist or is not attachable.${NC}"
        fi
    fi
done

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig for EKS cluster...${NC}"
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"

# Function to update aws-auth ConfigMap
update_aws_auth() {
    local cluster_name=$1
    local role_arn=$2
    
    echo -e "${YELLOW}Adding IAM role to aws-auth ConfigMap...${NC}"
    
    # Check if eksctl is installed
    if ! command -v eksctl &> /dev/null; then
        echo -e "${RED}eksctl not found. Installing...${NC}"
        
        # Install eksctl
        ARCH=$(uname -m)
        if [ "$ARCH" == "x86_64" ]; then
            curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
        else
            curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | tar xz -C /tmp
        fi
        
        sudo mv /tmp/eksctl /usr/local/bin
        
        if ! command -v eksctl &> /dev/null; then
            echo -e "${RED}Failed to install eksctl. Please manually update aws-auth ConfigMap.${NC}"
            echo -e "${YELLOW}Add this to your aws-auth ConfigMap:${NC}"
            echo "mapRoles:"
            echo "  - rolearn: ${role_arn}"
            echo "    username: github-actions"
            echo "    groups:"
            echo "      - system:masters"
            return 1
        fi
    fi
    
    # First try to delete any existing entry to avoid conflicts
    eksctl delete iamidentitymapping \
        --cluster "${cluster_name}" \
        --arn "${role_arn}" \
        --region "${AWS_REGION}" || true
    
    # Add the role to aws-auth ConfigMap
    if eksctl create iamidentitymapping \
        --cluster "${cluster_name}" \
        --region "${AWS_REGION}" \
        --arn "${role_arn}" \
        --username "github-actions" \
        --group "system:masters"; then
        echo -e "${GREEN}Successfully added role to aws-auth ConfigMap.${NC}"
    else
        echo -e "${RED}Failed to update aws-auth ConfigMap. Please do it manually.${NC}"
        return 1
    fi
    
    return 0
}

# Update aws-auth ConfigMap
update_aws_auth "${EKS_CLUSTER_NAME}" "${ROLE_ARN}"

# Create namespace if it doesn't exist
echo -e "${YELLOW}Creating namespace for your application...${NC}"
if ! kubectl get namespace "${GITHUB_REPO}" &> /dev/null; then
    kubectl create namespace "${GITHUB_REPO}"
    echo -e "${GREEN}Created namespace: ${GITHUB_REPO}${NC}"
else
    echo -e "${GREEN}Namespace ${GITHUB_REPO} already exists.${NC}"
fi

# Clean up temporary files
rm -f ecr-policy.json eks-policy.json k8s-api-policy.json alb-policy.json dns-policy.json trust-policy.json

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}GitHub Actions EKS permission setup completed successfully!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${YELLOW}Role ARN: ${ROLE_ARN}${NC}"
echo ""
echo -e "${YELLOW}Add these secrets to your GitHub repository:${NC}"
echo -e "${YELLOW}AWS_ROLE_ARN: ${ROLE_ARN}${NC}"
echo -e "${YELLOW}AWS_REGION: ${AWS_REGION}${NC}"
echo -e "${YELLOW}EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}${NC}"
echo ""
echo -e "${RED}Note: This role has permissions to manage your EKS cluster, ECR repositories,${NC}"
echo -e "${RED}load balancers, DNS records, and more. Review and adjust permissions if needed.${NC}"