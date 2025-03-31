#!/bin/bash
# github-iam-setup.sh - Script to create or update an IAM role for GitHub Actions
# Enhanced with comprehensive permissions for ECR, EKS, and DNS management

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
ECR_POLICY_NAME="ecr-access-$GITHUB_REPO-policy"
EKS_POLICY_NAME="eks-access-$GITHUB_REPO-policy"
DNS_POLICY_NAME="dns-access-$GITHUB_REPO-policy"
ALB_POLICY_NAME="alb-access-$GITHUB_REPO-policy"

# Text colors for formatting output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo -e "${GREEN}AWS Account ID: $ACCOUNT_ID${NC}"

# Create ECR policy with full permissions
echo -e "${YELLOW}Creating ECR access policy...${NC}"
cat > ecr-access-policy.json << EOF
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
            "Resource": "arn:aws:ecr:*:${ACCOUNT_ID}:repository/*"
        }
    ]
}
EOF

# Create EKS policy
echo -e "${YELLOW}Creating EKS access policy...${NC}"
cat > eks-access-policy.json << EOF
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
            "Resource": "arn:aws:eks:*:${ACCOUNT_ID}:cluster/*"
        }
    ]
}
EOF

# Create DNS policy for Route53 and ACM
echo -e "${YELLOW}Creating DNS access policy...${NC}"
cat > dns-access-policy.json << EOF
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
            "Resource": "arn:aws:acm:*:${ACCOUNT_ID}:certificate/*"
        }
    ]
}
EOF

# Create ALB Controller policy
echo -e "${YELLOW}Creating ALB access policy...${NC}"
cat > alb-access-policy.json << EOF
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

# Create or update a policy
create_or_update_policy() {
  local policy_name=$1
  local policy_document=$2
  
  # Check if policy exists
  if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}" &> /dev/null; then
    echo -e "${YELLOW}Policy ${policy_name} already exists, updating...${NC}"
    
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
    echo -e "${YELLOW}Creating new policy ${policy_name}...${NC}"
    POLICY_ARN=$(aws iam create-policy --policy-name $policy_name --policy-document file://${policy_document} --query "Policy.Arn" --output text)
  fi
  
  echo $POLICY_ARN
}

# Create or update all policies
ECR_POLICY_ARN=$(create_or_update_policy $ECR_POLICY_NAME "ecr-access-policy.json")
echo -e "${GREEN}ECR access policy created/updated: $ECR_POLICY_ARN${NC}"

EKS_POLICY_ARN=$(create_or_update_policy $EKS_POLICY_NAME "eks-access-policy.json")
echo -e "${GREEN}EKS access policy created/updated: $EKS_POLICY_ARN${NC}"

DNS_POLICY_ARN=$(create_or_update_policy $DNS_POLICY_NAME "dns-access-policy.json")
echo -e "${GREEN}DNS access policy created/updated: $DNS_POLICY_ARN${NC}"

ALB_POLICY_ARN=$(create_or_update_policy $ALB_POLICY_NAME "alb-access-policy.json")
echo -e "${GREEN}ALB access policy created/updated: $ALB_POLICY_ARN${NC}"

# Check if role exists
ROLE_EXISTS=false
if aws iam get-role --role-name $ROLE_NAME &> /dev/null; then
    ROLE_EXISTS=true
    echo -e "${YELLOW}Role $ROLE_NAME already exists${NC}"
else
    echo -e "${YELLOW}Role $ROLE_NAME does not exist, will create it${NC}"
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
    echo -e "${YELLOW}Creating GitHub Actions OIDC provider...${NC}"
    aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
    echo -e "${GREEN}OIDC provider created.${NC}"
else
    echo -e "${GREEN}GitHub Actions OIDC provider already exists.${NC}"
fi

# Create or update the IAM role
if [ "$ROLE_EXISTS" = true ]; then
    echo -e "${YELLOW}Updating existing role trust policy...${NC}"
    aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://trust-policy.json
else
    echo -e "${YELLOW}Creating new IAM role...${NC}"
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json
fi

# Function to attach policy to role with error handling
attach_policy_to_role() {
    local role_name=$1
    local policy_arn=$2
    local policy_name=$(echo $policy_arn | awk -F '/' '{print $2}')
    
    echo -e "${YELLOW}Attaching $policy_name to role...${NC}"
    
    # Check if policy is already attached
    POLICY_ATTACHED=$(aws iam list-attached-role-policies --role-name $role_name --query "AttachedPolicies[?PolicyArn=='$policy_arn'].PolicyArn" --output text)
    
    if [ -n "$POLICY_ATTACHED" ]; then
        echo -e "${GREEN}Policy $policy_name already attached to role.${NC}"
    else
        aws iam attach-role-policy --role-name $role_name --policy-arn $policy_arn
        echo -e "${GREEN}Policy $policy_name attached to role.${NC}"
    fi
}

# Attach all policies to the role
attach_policy_to_role $ROLE_NAME $ECR_POLICY_ARN
attach_policy_to_role $ROLE_NAME $EKS_POLICY_ARN
attach_policy_to_role $ROLE_NAME $DNS_POLICY_ARN
attach_policy_to_role $ROLE_NAME $ALB_POLICY_ARN

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo -e "${GREEN}IAM role updated: $ROLE_ARN${NC}"

# Add the role to the EKS cluster auth configmap
read -p "Do you want to add this role to the EKS cluster's aws-auth ConfigMap? (y/n): " ADD_TO_EKS
if [[ "$ADD_TO_EKS" == "y" || "$ADD_TO_EKS" == "Y" ]]; then
    read -p "Enter your EKS cluster name: " EKS_CLUSTER_NAME
    
    # Update kubeconfig first
    echo -e "${YELLOW}Updating kubeconfig...${NC}"
    aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
    
    # Check if eksctl is installed
    if command -v eksctl &> /dev/null; then
        # Use eksctl to add IAM role to EKS cluster (this is idempotent)
        echo -e "${YELLOW}Adding role to EKS cluster auth using eksctl...${NC}"
        eksctl create iamidentitymapping \
            --cluster $EKS_CLUSTER_NAME \
            --arn $ROLE_ARN \
            --username github-actions \
            --group system:masters
        
        echo -e "${GREEN}Role added to EKS cluster auth.${NC}"
    else
        echo -e "${RED}eksctl not found. Please install eksctl and run:${NC}"
        echo "eksctl create iamidentitymapping --cluster $EKS_CLUSTER_NAME --arn $ROLE_ARN --username github-actions --group system:masters"
    fi
fi

# Clean up
rm -f ecr-access-policy.json eks-access-policy.json dns-access-policy.json alb-access-policy.json trust-policy.json

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}Setup complete! The following policies have been attached to your role:${NC}"
echo -e "${GREEN}- ECR access policy: $ECR_POLICY_ARN${NC}"
echo -e "${GREEN}- EKS access policy: $EKS_POLICY_ARN${NC}"
echo -e "${GREEN}- DNS access policy: $DNS_POLICY_ARN${NC}"
echo -e "${GREEN}- ALB access policy: $ALB_POLICY_ARN${NC}"
echo ""
echo -e "${YELLOW}Add the following secrets to your GitHub repository:${NC}"
echo -e "${YELLOW}AWS_ROLE_ARN: $ROLE_ARN${NC}"
echo -e "${YELLOW}AWS_REGION: <your-aws-region>${NC}"
echo -e "${YELLOW}EKS_CLUSTER_NAME: <your-eks-cluster-name>${NC}"
echo -e "${YELLOW}DOMAIN_NAME: <your-domain-name>${NC}"
echo -e "${YELLOW}HOSTED_ZONE_ID: <your-hosted-zone-id>${NC}"