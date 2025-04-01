#!/bin/bash
# github-eks-permissions-fixed-arn.sh - Comprehensive script to set up GitHub Actions permissions for EKS
# Run this after eks-setup.sh to properly configure IAM roles and permissions
# With added verification steps for policy file creation and ARN handling

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

# Policy files
ECR_POLICY_FILE="ecr-policy.json"
EKS_POLICY_FILE="eks-policy.json"
K8S_API_POLICY_FILE="k8s-api-policy.json"
ALB_POLICY_FILE="alb-policy.json"
DNS_POLICY_FILE="dns-policy.json"
TRUST_POLICY_FILE="trust-policy.json"

echo -e "${YELLOW}Starting comprehensive GitHub Actions EKS permission setup...${NC}"

# Function to verify file creation
verify_file() {
    local file=$1
    local description=$2
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Failed to create $description file: $file${NC}"
        exit 1
    fi
    
    # Check if file is valid JSON
    if ! jq empty "$file" 2>/dev/null; then
        echo -e "${RED}Error: $description file is not valid JSON: $file${NC}"
        echo -e "${RED}File contents:${NC}"
        cat "$file"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully created and verified $description file: $file${NC}"
}

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
echo -e "${YELLOW}Creating ECR Policy file: ${ECR_POLICY_FILE}${NC}"
cat > ${ECR_POLICY_FILE} << EOF
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
verify_file "${ECR_POLICY_FILE}" "ECR policy"

# EKS Policy
echo -e "${YELLOW}Creating EKS Policy file: ${EKS_POLICY_FILE}${NC}"
cat > ${EKS_POLICY_FILE} << EOF
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
verify_file "${EKS_POLICY_FILE}" "EKS policy"

# Kubernetes API Policy
echo -e "${YELLOW}Creating Kubernetes API Policy file: ${K8S_API_POLICY_FILE}${NC}"
cat > ${K8S_API_POLICY_FILE} << EOF
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
verify_file "${K8S_API_POLICY_FILE}" "Kubernetes API policy"

# ALB Policy
echo -e "${YELLOW}Creating ALB Policy file: ${ALB_POLICY_FILE}${NC}"
cat > ${ALB_POLICY_FILE} << EOF
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
verify_file "${ALB_POLICY_FILE}" "ALB policy"

# Create DNS Policy
echo -e "${YELLOW}Creating DNS Policy file: ${DNS_POLICY_FILE}${NC}"
cat > ${DNS_POLICY_FILE} << EOF
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
verify_file "${DNS_POLICY_FILE}" "DNS policy"

# Function to create or update policy - FIXED ARN HANDLING
create_or_update_policy() {
    local policy_name=$1
    local description=$2
    local policy_file=$3
    
    # Verify the policy file exists before proceeding
    if [ ! -f "${policy_file}" ]; then
        echo -e "${RED}Error: Policy file ${policy_file} does not exist!${NC}"
        exit 1
    fi
    
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
        echo "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    else
        echo -e "${YELLOW}Creating new policy: ${policy_name}${NC}"
        # Store the result in a variable and check for errors
        RESULT=$(aws iam create-policy \
            --policy-name "${policy_name}" \
            --description "${description}" \
            --policy-document file://${policy_file} \
            --query 'Policy.Arn' \
            --output text 2>&1)
            
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error creating policy ${policy_name}: ${RESULT}${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Created policy: ${RESULT}${NC}"
        echo "${RESULT}"
    fi
}

# Create the policies
echo -e "${YELLOW}Creating and verifying policies...${NC}"
ECR_POLICY_NAME="github-actions-${GITHUB_REPO}-ecr-policy"
EKS_POLICY_NAME="github-actions-${GITHUB_REPO}-eks-policy"
K8S_POLICY_NAME="github-actions-${GITHUB_REPO}-k8s-api-policy"
ALB_POLICY_NAME="github-actions-${GITHUB_REPO}-alb-policy"
DNS_POLICY_NAME="github-actions-${GITHUB_REPO}-dns-policy"

# Create policies with verified files
ECR_POLICY_ARN=$(create_or_update_policy "$ECR_POLICY_NAME" "ECR access for GitHub Actions" "${ECR_POLICY_FILE}")
echo -e "${YELLOW}ECR Policy ARN: ${ECR_POLICY_ARN}${NC}"

EKS_POLICY_ARN=$(create_or_update_policy "$EKS_POLICY_NAME" "EKS access for GitHub Actions" "${EKS_POLICY_FILE}")
echo -e "${YELLOW}EKS Policy ARN: ${EKS_POLICY_ARN}${NC}"

K8S_POLICY_ARN=$(create_or_update_policy "$K8S_POLICY_NAME" "Kubernetes API access for GitHub Actions" "${K8S_API_POLICY_FILE}")
echo -e "${YELLOW}K8s API Policy ARN: ${K8S_POLICY_ARN}${NC}"

ALB_POLICY_ARN=$(create_or_update_policy "$ALB_POLICY_NAME" "ALB and network access for GitHub Actions" "${ALB_POLICY_FILE}")
echo -e "${YELLOW}ALB Policy ARN: ${ALB_POLICY_ARN}${NC}"

DNS_POLICY_ARN=$(create_or_update_policy "$DNS_POLICY_NAME" "DNS and Route53 access for GitHub Actions" "${DNS_POLICY_FILE}")
echo -e "${YELLOW}DNS Policy ARN: ${DNS_POLICY_ARN}${NC}"

# Create trust policy for the role
echo -e "${YELLOW}Creating Trust Policy file: ${TRUST_POLICY_FILE}${NC}"
cat > ${TRUST_POLICY_FILE} << EOF
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
verify_file "${TRUST_POLICY_FILE}" "Trust policy"

# Check if role exists
echo -e "${YELLOW}Setting up IAM role with OIDC trust relationship...${NC}"
if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
    echo -e "${YELLOW}Updating existing IAM role: ${ROLE_NAME}${NC}"
    aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document file://${TRUST_POLICY_FILE}
else
    echo -e "${YELLOW}Creating new IAM role: ${ROLE_NAME}${NC}"
    aws iam create-role --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://${TRUST_POLICY_FILE} \
        --description "Role for GitHub Actions to access AWS resources" > /dev/null
fi

ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query "Role.Arn" --output text)
echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"

# Function to safely attach policy to role - FIXED ARN HANDLING
attach_policy_to_role() {
    local role_name=$1
    local policy_arn=$2
    
    # Verify policy ARN looks valid
    if [ -z "$policy_arn" ]; then
        echo -e "${RED}Error: Empty policy ARN${NC}"
        return 1
    fi
    
    # Extract policy name for display
    local policy_name=$(basename "$policy_arn")
    
    echo -e "${YELLOW}Attaching policy: ${policy_name} (${policy_arn})${NC}"
    
    # Check if policy is already attached
    if aws iam list-attached-role-policies --role-name "${role_name}" | grep -q "${policy_arn}"; then
        echo -e "${GREEN}Policy already attached: ${policy_name}${NC}"
    else
        if aws iam attach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}"; then
            echo -e "${GREEN}Successfully attached policy: ${policy_name}${NC}"
        else
            echo -e "${RED}Failed to attach policy: ${policy_name}${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Attach policies to the role
echo -e "${YELLOW}Attaching policies to the role...${NC}"
ATTACH_ERRORS=0

attach_policy_to_role "${ROLE_NAME}" "${ECR_POLICY_ARN}" || ((ATTACH_ERRORS++))
attach_policy_to_role "${ROLE_NAME}" "${EKS_POLICY_ARN}" || ((ATTACH_ERRORS++))
attach_policy_to_role "${ROLE_NAME}" "${K8S_POLICY_ARN}" || ((ATTACH_ERRORS++))
attach_policy_to_role "${ROLE_NAME}" "${ALB_POLICY_ARN}" || ((ATTACH_ERRORS++))
attach_policy_to_role "${ROLE_NAME}" "${DNS_POLICY_ARN}" || ((ATTACH_ERRORS++))

if [ $ATTACH_ERRORS -gt 0 ]; then
    echo -e "${RED}Warning: ${ATTACH_ERRORS} policy attachment errors occurred.${NC}"
fi

# Also try to attach AWS managed policies
echo -e "${YELLOW}Attaching AWS managed policies...${NC}"
AWS_MANAGED_POLICIES=(
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
)

for policy_arn in "${AWS_MANAGED_POLICIES[@]}"; do
    policy_name=$(basename "$policy_arn")
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

# Function to handle aws-auth ConfigMap updates
update_eks_auth_config() {
    echo -e "${YELLOW}Removing any existing role mappings to avoid duplicates...${NC}"
    # Try to remove existing mappings, but don't fail if none exist
    eksctl delete iamidentitymapping --cluster="${EKS_CLUSTER_NAME}" --arn="${ROLE_ARN}" || true
    
    # Add the IAM role to the aws-auth ConfigMap
    echo -e "${YELLOW}Adding IAM role to aws-auth ConfigMap...${NC}"
    
    if eksctl create iamidentitymapping \
        --cluster "${EKS_CLUSTER_NAME}" \
        --arn="${ROLE_ARN}" \
        --username="github-actions" \
        --group="system:masters"; then
        echo -e "${GREEN}Successfully added role to aws-auth ConfigMap.${NC}"
        return 0
    else
        echo -e "${RED}Failed to update aws-auth ConfigMap with eksctl. Trying alternative method...${NC}"
        return 1
    fi
}

# Try to update aws-auth ConfigMap
update_eks_auth_config || {
    echo -e "${YELLOW}Attempting manual update of aws-auth ConfigMap...${NC}"
    
    # Get current aws-auth ConfigMap
    if kubectl -n kube-system get configmap aws-auth -o yaml > aws-auth-current.yaml; then
        # Set up markers to help with sed replacement
        START_MARKER="# --- GITHUB ACTIONS ROLE START ---"
        END_MARKER="# --- GITHUB ACTIONS ROLE END ---"
        
        # Check if the markers already exist in the ConfigMap
        if grep -q "${START_MARKER}" aws-auth-current.yaml; then
            # Update the existing entry
            sed -i "/${START_MARKER}/,/${END_MARKER}/c\\
${START_MARKER}\\
    - groups:\\
      - system:masters\\
      rolearn: ${ROLE_ARN}\\
      username: github-actions\\
${END_MARKER}" aws-auth-current.yaml
        else
            # Add a new entry
            sed -i "/mapRoles: |/a\\
${START_MARKER}\\
    - groups:\\
      - system:masters\\
      rolearn: ${ROLE_ARN}\\
      username: github-actions\\
${END_MARKER}" aws-auth-current.yaml
        fi
        
        # Apply the updated ConfigMap
        kubectl apply -f aws-auth-current.yaml
        rm aws-auth-current.yaml
    else
        echo -e "${RED}Unable to get aws-auth ConfigMap. You may need to update it manually.${NC}"
        echo -e "${RED}Add the following to the aws-auth ConfigMap:${NC}"
        echo "mapRoles:"
        echo "  - rolearn: ${ROLE_ARN}"
        echo "    username: github-actions"
        echo "    groups:"
        echo "      - system:masters"
    fi
}

# Create namespace if it doesn't exist
echo -e "${YELLOW}Creating namespace for your application...${NC}"
if ! kubectl get namespace "${GITHUB_REPO}" &> /dev/null; then
    kubectl create namespace "${GITHUB_REPO}"
    echo -e "${GREEN}Created namespace: ${GITHUB_REPO}${NC}"
else
    echo -e "${GREEN}Namespace ${GITHUB_REPO} already exists.${NC}"
fi

# List and verify all attached policies for final confirmation
echo -e "${YELLOW}Verifying attached policies for role ${ROLE_NAME}...${NC}"
aws iam list-attached-role-policies --role-name "${ROLE_NAME}"

# Clean up temporary files
echo -e "${YELLOW}Cleaning up temporary policy files...${NC}"
rm -f ${ECR_POLICY_FILE} ${EKS_POLICY_FILE} ${K8S_API_POLICY_FILE} ${ALB_POLICY_FILE} ${DNS_POLICY_FILE} ${TRUST_POLICY_FILE}

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