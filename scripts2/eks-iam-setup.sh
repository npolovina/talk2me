#!/bin/bash
# comprehensive-github-eks-setup.sh - Complete setup for GitHub Actions with EKS

set -e

# Configuration - MODIFY THESE VALUES
GITHUB_ORG="npolovina"
GITHUB_REPO="talk2me"
EKS_CLUSTER_NAME="talk2me"
AWS_REGION="us-east-1" 
ROLE_NAME="github-actions-talk2me-role"

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting comprehensive GitHub Actions EKS setup script...${NC}"

# Check for required tools
command -v aws >/dev/null 2>&1 || { echo -e "${RED}Error: AWS CLI is required but not installed.${NC}" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq is required but not installed.${NC}" >&2; exit 1; }

# Verify AWS credentials
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text) || { 
    echo -e "${RED}Error: Could not retrieve AWS account ID. Please check your AWS credentials.${NC}" >&2
    exit 1
}
echo -e "${GREEN}Using AWS Account: ${AWS_ACCOUNT_ID}${NC}"

# Check if the EKS cluster exists
echo -e "${YELLOW}Verifying EKS cluster exists...${NC}"
if ! aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo -e "${RED}Error: EKS cluster '${EKS_CLUSTER_NAME}' does not exist in region '${AWS_REGION}'.${NC}" >&2
    exit 1
fi
echo -e "${GREEN}EKS cluster '${EKS_CLUSTER_NAME}' found.${NC}"

# 1. Create or update the GitHub OIDC provider
echo -e "${YELLOW}Setting up GitHub OIDC provider...${NC}"
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

# 2. Create IAM policies for the role
echo -e "${YELLOW}Creating IAM policies...${NC}"

# Create ECR policy
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

# Create EKS policy with comprehensive permissions
cat > eks-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups",
                "eks:ListUpdates",
                "eks:AccessKubernetesApi"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "eks:UpdateClusterConfig",
                "eks:UpdateNodegroupConfig"
            ],
            "Resource": "arn:aws:eks:*:${AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:PassedToService": "eks.amazonaws.com"
                }
            }
        }
    ]
}
EOF

# Create Kubernetes API access policy for EKS
cat > k8s-api-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster"
            ],
            "Resource": "arn:aws:eks:*:${AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
        }
    ]
}
EOF

# Policy for ALB and related services
cat > alb-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:*",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeRouteTables",
                "ec2:DescribeInternetGateways"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create a function to create or update policies with improved error handling
create_or_update_policy() {
    local policy_name=$1
    local policy_file=$2
    local policy_description=$3
    
    echo -e "${YELLOW}Setting up ${policy_description} policy...${NC}"
    
    # Check if policy exists
    POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='${policy_name}'].Arn" --output text)
    
    if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" == "None" ]; then
        # Create new policy
        echo -e "${YELLOW}Creating new policy: ${policy_name}${NC}"
        POLICY_ARN=$(aws iam create-policy \
            --policy-name "${policy_name}" \
            --policy-document file://${policy_file} \
            --description "${policy_description}" \
            --query "Policy.Arn" --output text)
            
        if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" == "None" ]; then
            echo -e "${RED}Failed to create policy: ${policy_name}${NC}"
            return 1
        fi
        
        echo -e "${GREEN}Created policy: ${POLICY_ARN}${NC}"
    else
        # Update existing policy
        echo -e "${YELLOW}Updating existing policy: ${policy_name}${NC}"
        
        # Get current version
        CURRENT_VERSION=$(aws iam get-policy --policy-arn "${POLICY_ARN}" --query "Policy.DefaultVersionId" --output text)
        
        # List policy versions
        VERSION_COUNT=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" --query "length(Versions)" --output text)
        
        # If we have 5 versions (the max), delete the oldest non-default version
        if [ "$VERSION_COUNT" -ge "5" ]; then
            # Find the oldest non-default version
            OLDEST_VERSION=$(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
                --query "Versions[?IsDefaultVersion==\`false\`] | sort_by(@, &CreateDate)[0].VersionId" --output text)
            
            if [ -n "$OLDEST_VERSION" ] && [ "$OLDEST_VERSION" != "None" ]; then
                echo -e "${YELLOW}Deleting oldest policy version: ${OLDEST_VERSION}${NC}"
                aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${OLDEST_VERSION}"
            fi
        fi
        
        # Create new policy version
        aws iam create-policy-version \
            --policy-arn "${POLICY_ARN}" \
            --policy-document file://${policy_file} \
            --set-as-default
        
        echo -e "${GREEN}Updated policy: ${POLICY_ARN}${NC}"
    fi
    
    echo "$POLICY_ARN"
}

# Create the policies with error checking
ECR_POLICY_NAME="${ROLE_NAME}-ecr-policy"
ECR_POLICY_ARN=$(create_or_update_policy "${ECR_POLICY_NAME}" "ecr-policy.json" "ECR access for GitHub Actions")
if [ -z "$ECR_POLICY_ARN" ] || [ "$ECR_POLICY_ARN" == "None" ]; then
    echo -e "${RED}Failed to create ECR policy. Exiting.${NC}"
    exit 1
fi

EKS_POLICY_NAME="${ROLE_NAME}-eks-policy"
EKS_POLICY_ARN=$(create_or_update_policy "${EKS_POLICY_NAME}" "eks-policy.json" "EKS access for GitHub Actions")
if [ -z "$EKS_POLICY_ARN" ] || [ "$EKS_POLICY_ARN" == "None" ]; then
    echo -e "${RED}Failed to create EKS policy. Exiting.${NC}"
    exit 1
fi

K8S_API_POLICY_NAME="${ROLE_NAME}-k8s-api-policy"
K8S_API_POLICY_ARN=$(create_or_update_policy "${K8S_API_POLICY_NAME}" "k8s-api-policy.json" "Kubernetes API access for GitHub Actions")
if [ -z "$K8S_API_POLICY_ARN" ] || [ "$K8S_API_POLICY_ARN" == "None" ]; then
    echo -e "${RED}Failed to create K8s API policy. Exiting.${NC}"
    exit 1
fi

ALB_POLICY_NAME="${ROLE_NAME}-alb-policy"
ALB_POLICY_ARN=$(create_or_update_policy "${ALB_POLICY_NAME}" "alb-policy.json" "ALB and network access for GitHub Actions")
if [ -z "$ALB_POLICY_ARN" ] || [ "$ALB_POLICY_ARN" == "None" ]; then
    echo -e "${RED}Failed to create ALB policy. Exiting.${NC}"
    exit 1
fi

# Verify policy ARNs
echo -e "${YELLOW}Verifying policy ARNs...${NC}"
echo "ECR Policy ARN: ${ECR_POLICY_ARN}"
echo "EKS Policy ARN: ${EKS_POLICY_ARN}"
echo "K8s API Policy ARN: ${K8S_API_POLICY_ARN}"
echo "ALB Policy ARN: ${ALB_POLICY_ARN}"

# 3. Create or update IAM role with OIDC trust relationship
echo -e "${YELLOW}Setting up IAM role with OIDC trust relationship...${NC}"

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
ROLE_EXISTS=$(aws iam get-role --role-name "${ROLE_NAME}" 2>&1 || echo "NOT_FOUND")

if [[ "$ROLE_EXISTS" == *"NoSuchEntity"* ]] || [[ "$ROLE_EXISTS" == "NOT_FOUND" ]]; then
    # Create new role
    echo -e "${YELLOW}Creating new IAM role: ${ROLE_NAME}${NC}"
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for GitHub Actions to access EKS and ECR"
else
    # Update existing role
    echo -e "${YELLOW}Updating existing IAM role: ${ROLE_NAME}${NC}"
    aws iam update-assume-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-document file://trust-policy.json
fi

# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name "${ROLE_NAME}" --query "Role.Arn" --output text)
echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"

# 4. Attach policies to the role with improved error handling
echo -e "${YELLOW}Attaching policies to the role...${NC}"

# Function to attach policy if not already attached
attach_policy() {
    local role_name=$1
    local policy_arn=$2
    
    if [ -z "$policy_arn" ] || [ "$policy_arn" == "None" ]; then
        echo -e "${RED}Cannot attach empty or invalid policy ARN to role.${NC}"
        return 1
    fi
    
    local policy_name=$(echo $policy_arn | awk -F/ '{print $NF}')
    
    echo -e "${YELLOW}Attaching policy: ${policy_name} (${policy_arn})${NC}"
    
    # Check if policy is already attached
    IS_ATTACHED=$(aws iam list-attached-role-policies --role-name "${role_name}" \
        --query "AttachedPolicies[?PolicyArn=='${policy_arn}'].PolicyArn" --output text)
    
    if [ -z "$IS_ATTACHED" ]; then
        aws iam attach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to attach policy: ${policy_name}${NC}"
            return 1
        fi
        echo -e "${GREEN}Attached policy: ${policy_name}${NC}"
    else
        echo -e "${GREEN}Policy already attached: ${policy_name}${NC}"
    fi
    
    return 0
}

# Attach our custom policies
attach_policy "${ROLE_NAME}" "${ECR_POLICY_ARN}" || echo -e "${RED}Failed to attach ECR policy.${NC}"
attach_policy "${ROLE_NAME}" "${EKS_POLICY_ARN}" || echo -e "${RED}Failed to attach EKS policy.${NC}"
attach_policy "${ROLE_NAME}" "${K8S_API_POLICY_ARN}" || echo -e "${RED}Failed to attach K8s API policy.${NC}"
attach_policy "${ROLE_NAME}" "${ALB_POLICY_ARN}" || echo -e "${RED}Failed to attach ALB policy.${NC}"

# Attach AWS managed policies that might be needed
attach_policy "${ROLE_NAME}" "arn:aws:iam::aws:policy/AmazonECR-FullAccess" || echo -e "${RED}Failed to attach ECR-FullAccess policy.${NC}"
attach_policy "${ROLE_NAME}" "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" || echo -e "${RED}Failed to attach EKSClusterPolicy.${NC}"

# 5. Update EKS cluster aws-auth configmap
echo -e "${YELLOW}Updating EKS cluster aws-auth ConfigMap...${NC}"

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig for EKS cluster...${NC}"
aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}"

# Check if eksctl is installed
if ! command -v eksctl &>/dev/null; then
    echo -e "${RED}Warning: eksctl is not installed. It's needed to update the aws-auth ConfigMap.${NC}"
    echo -e "${YELLOW}Installing eksctl...${NC}"
    
    # Install eksctl (simplified version, adjust if needed)
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    elif [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
        curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_arm64.tar.gz" | tar xz -C /tmp
    else
        echo -e "${RED}Unsupported architecture: ${ARCH}. Please install eksctl manually.${NC}"
        exit 1
    fi
    
    sudo mv /tmp/eksctl /usr/local/bin
    
    if ! command -v eksctl &>/dev/null; then
        echo -e "${RED}Failed to install eksctl. Please install it manually and run this script again.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}eksctl installed successfully.${NC}"
fi

# Add IAM role to aws-auth ConfigMap
echo -e "${YELLOW}Adding IAM role to aws-auth ConfigMap...${NC}"
eksctl create iamidentitymapping \
    --cluster "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --arn "${ROLE_ARN}" \
    --username "github-actions-${GITHUB_REPO}" \
    --group "system:masters" \
    --no-duplicate-arns

echo -e "${GREEN}IAM role added to aws-auth ConfigMap.${NC}"

# 6. Create namespace for the application if it doesn't exist
echo -e "${YELLOW}Creating namespace for the application...${NC}"
kubectl create namespace talk2me --dry-run=client -o yaml | kubectl apply -f -

# Create a script to add the EKS cluster credentials to the role
cat > verify-access.sh << EOF
#!/bin/bash
# Test script to verify role permissions

# Set environment variables
export AWS_ROLE_ARN="${ROLE_ARN}"
export AWS_REGION="${AWS_REGION}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}"

# Assume the role
echo "Assuming role: ${AWS_ROLE_ARN}"
CREDS=\$(aws sts assume-role --role-arn \${AWS_ROLE_ARN} --role-session-name "TestSession" --query "Credentials" --output json)

# Extract credentials
export AWS_ACCESS_KEY_ID=\$(echo \$CREDS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=\$(echo \$CREDS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=\$(echo \$CREDS | jq -r '.SessionToken')

# Test EKS access
echo "Testing EKS access..."
aws eks describe-cluster --name \${EKS_CLUSTER_NAME} --region \${AWS_REGION}

# Update kubeconfig for EKS
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name \${EKS_CLUSTER_NAME} --region \${AWS_REGION}

# Test kubectl commands
echo "Testing kubectl commands..."
kubectl get namespace talk2me
kubectl auth can-i get configmap -n kube-system

# Clean up
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
EOF

chmod +x verify-access.sh
echo -e "${GREEN}Created verification script: verify-access.sh${NC}"

# Clean up policy files
rm -f ecr-policy.json eks-policy.json k8s-api-policy.json alb-policy.json trust-policy.json

echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}GitHub Actions EKS setup completed successfully!${NC}"
echo -e "${GREEN}==============================================${NC}"
echo
echo -e "${YELLOW}Add the following secrets to your GitHub repository:${NC}"
echo -e "${YELLOW}AWS_ROLE_ARN: ${ROLE_ARN}${NC}"
echo -e "${YELLOW}AWS_REGION: ${AWS_REGION}${NC}"
echo -e "${YELLOW}EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}${NC}"
echo
echo -e "${YELLOW}To verify the setup, run:${NC}"
echo -e "${YELLOW}./verify-access.sh${NC}"
echo
echo -e "${YELLOW}Your GitHub Actions workflow can now use these secrets to deploy to EKS.${NC}"