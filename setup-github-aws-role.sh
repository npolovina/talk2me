#!/bin/bash
set -e

# Variables - adjust these
ROLE_NAME="github-actions-talk2me-role"
GITHUB_ORG="npolovina"
GITHUB_REPO="talk2me"
GITHUB_BRANCH="main"  # Change as needed, or use "*" for all branches
AWS_REGION="us-east-1"  # Change to your desired region
IAM_PERMISSION_POLICY_NAME="${ROLE_NAME}-policy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Creating AWS IAM role for GitHub Actions OIDC authentication...${NC}"

# Create trust policy for GitHub Actions OIDC
echo -e "${YELLOW}Creating trust policy...${NC}"
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}"
        }
      }
    }
  ]
}
EOF

# Check if the role already exists
ROLE_EXISTS=$(aws iam get-role --role-name ${ROLE_NAME} 2>&1 || echo "NOT_FOUND")

if [[ $ROLE_EXISTS == *"NoSuchEntity"* ]] || [[ $ROLE_EXISTS == "NOT_FOUND" ]]; then
  # Create the IAM role
  echo -e "${YELLOW}Creating IAM role: ${ROLE_NAME}...${NC}"
  aws iam create-role --role-name ${ROLE_NAME} --assume-role-policy-document file://trust-policy.json
else
  echo -e "${YELLOW}Updating trust policy for existing role: ${ROLE_NAME}...${NC}"
  aws iam update-assume-role-policy --role-name ${ROLE_NAME} --policy-document file://trust-policy.json
fi

# Create permissions policy
echo -e "${YELLOW}Creating permissions policy...${NC}"
cat > permissions-policy.json << EOF
# Create permissions policy
echo "Creating permissions policy..."
cat > permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "eks:*",
        "ec2:*",
        "elasticloadbalancing:*",
        "iam:ListRoles",
        "iam:GetRole",
        "iam:PassRole",
        "ecr:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create the policy
POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_PERMISSION_POLICY_NAME} --policy-document file://permissions-policy.json --query 'Policy.Arn' --output text)
EOF

# Check if the policy already exists
POLICY_EXISTS=$(aws iam list-policies --query "Policies[?PolicyName=='${IAM_PERMISSION_POLICY_NAME}'].Arn" --output text)

if [ -z "$POLICY_EXISTS" ]; then
  # Create the policy
  echo -e "${YELLOW}Creating new IAM policy: ${IAM_PERMISSION_POLICY_NAME}...${NC}"
  POLICY_ARN=$(aws iam create-policy --policy-name ${IAM_PERMISSION_POLICY_NAME} --policy-document file://permissions-policy.json --query 'Policy.Arn' --output text)
else
  echo -e "${YELLOW}IAM policy ${IAM_PERMISSION_POLICY_NAME} already exists, updating...${NC}"
  POLICY_ARN=$POLICY_EXISTS
  
  # Get the current version
  POLICY_VERSION=$(aws iam get-policy --policy-arn ${POLICY_ARN} --query 'Policy.DefaultVersionId' --output text)
  
  # Create a new version
  aws iam create-policy-version --policy-arn ${POLICY_ARN} --policy-document file://permissions-policy.json --set-as-default
  
  # Delete the old version if it's not v1
  if [ "$POLICY_VERSION" != "v1" ]; then
    aws iam delete-policy-version --policy-arn ${POLICY_ARN} --version-id ${POLICY_VERSION}
  fi
fi

# Attach the policy to the role
echo -e "${YELLOW}Attaching policy to role...${NC}"
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn ${POLICY_ARN}

# Output role ARN for GitHub Actions workflow
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)
echo -e "${GREEN}Setup complete!${NC}"
echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"
echo -e "${YELLOW}Use this Role ARN in your GitHub Actions workflow:${NC}"
echo -e "${GREEN}role-to-assume: ${ROLE_ARN}${NC}"

# Cleanup
rm -f trust-policy.json permissions-policy.json

