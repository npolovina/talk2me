# EKS Cluster Authentication Guide

This guide provides step-by-step instructions for authenticating to an AWS EKS cluster using IAM role assumption.

## Prerequisites

- AWS CLI (installed and configured with base credentials)
- kubectl
- jq (for parsing JSON responses)
- Access to an AWS account with sufficient permissions

## 1. Fix IAM Permissions

If you encounter an `AccessDenied` error when trying to assume a role, you need to update the trust relationship.

### Automated Method

1. Save the script below as `update-role-permissions.sh`
2. Make it executable: `chmod +x update-role-permissions.sh`
3. Run it: `./update-role-permissions.sh`

```bash
#!/bin/bash

# Script to update IAM role trust relationship
# This script adds the GitHub-Actions-User to the trust policy of GitHub-Actions-Talk2Me-Role

# Set variables
ROLE_NAME="GitHub-Actions-Talk2Me-Role"
USER_ARN="arn:aws:iam::637423575947:user/GitHub-Actions-User"
ACCOUNT_ID="637423575947"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated with AWS
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Not authenticated with AWS. Please run 'aws configure' first."
    exit 1
fi

echo "Updating trust relationship for role: $ROLE_NAME"

# Get current trust policy
CURRENT_POLICY=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "Failed to get current trust policy. Check if the role exists and you have permission to view it."
    exit 1
fi

echo "Current trust policy: $CURRENT_POLICY"

# Create a new trust policy that includes the GitHub-Actions-User
cat > new-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$USER_ARN"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

echo "Created new trust policy. Updating role..."

# Update the role with the new trust policy
if aws iam update-assume-role-policy --role-name $ROLE_NAME --policy-document file://new-trust-policy.json; then
    echo "Successfully updated trust policy for role: $ROLE_NAME"
else
    echo "Failed to update trust policy. Check if you have the necessary permissions."
    exit 1
fi

# Add permission to the user to assume the role
echo "Adding permission to GitHub-Actions-User to assume the role..."

cat > assume-role-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
    }
  ]
}
EOF

if aws iam put-user-policy --user-name GitHub-Actions-User --policy-name AssumeRolePolicy --policy-document file://assume-role-policy.json; then
    echo "Successfully added assume role policy to user: GitHub-Actions-User"
else
    echo "Failed to add assume role policy to user. Check if you have the necessary permissions."
    exit 1
fi

# Clean up temporary files
rm -f new-trust-policy.json assume-role-policy.json

echo "Script completed. Try using the role now with:"
echo "aws eks get-token --cluster-name talk2me-cluster --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

# Test the assume role
echo "Testing the role assumption..."
if aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME --role-session-name test-session &> /dev/null; then
    echo "Role assumption test successful!"
else
    echo "Role assumption test failed. You may need to wait a few seconds for the changes to propagate."
fi
```

### Manual Method

If you prefer to update the permissions manually:

1. Update the role's trust relationship:
```bash
aws iam update-assume-role-policy --role-name GitHub-Actions-Talk2Me-Role --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::637423575947:user/GitHub-Actions-User"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'
```

2. Add permissions to your user:
```bash
aws iam put-user-policy --user-name GitHub-Actions-User --policy-name AssumeRolePolicy --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::637423575947:role/GitHub-Actions-Talk2Me-Role"
    }
  ]
}'
```

## 2. Authenticate to the EKS Cluster

After fixing the permissions, follow these steps to authenticate to your EKS cluster:

### Step 1: Test Role Assumption

Verify you can assume the role:
```bash
aws sts assume-role --role-arn arn:aws:iam::637423575947:role/GitHub-Actions-Talk2Me-Role --role-session-name eks-session
```

This should return temporary credentials if successful.

### Step 2: Update Kubeconfig

Configure kubectl to use your EKS cluster with the assumed role:
```bash
aws eks update-kubeconfig --name talk2me-cluster --region us-east-1 --role-arn arn:aws:iam::637423575947:role/GitHub-Actions-Talk2Me-Role
```

### Step 3: Verify Configuration

Check that your kubeconfig was updated correctly:
```bash
kubectl config view
```

### Step 4: Test Cluster Access

Try accessing your cluster:
```bash
kubectl get nodes
```

## Troubleshooting

If you encounter issues, try the following methods:

### Method 1: Use Environment Variables

```bash
# Assume the role and store temporary credentials
CREDENTIALS=$(aws sts assume-role --role-arn arn:aws:iam::637423575947:role/GitHub-Actions-Talk2Me-Role --role-session-name eks-session)

# Export the credentials
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Credentials.SessionToken')

# Now try to access the cluster
kubectl get pods -n kube-system
```

### Method 2: One-line Authentication

```bash
aws eks get-token --cluster-name talk2me-cluster --role-arn arn:aws:iam::637423575947:role/GitHub-Actions-Talk2Me-Role | kubectl get pods -n kube-system --token $(jq -r '.status.token' -)
```

### Common Issues

1. **Error: "Unhandled Error"** - Usually indicates a connectivity issue to the EKS API server
2. **Error: "AccessDenied"** - Permissions issue with the IAM role
3. **Error: "No such host"** - DNS resolution issue or incorrect cluster name

## Additional Resources

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html)
- [IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Troubleshooting EKS Authentication](https://aws.amazon.com/premiumsupport/knowledge-center/eks-api-server-unauthorized-error/)