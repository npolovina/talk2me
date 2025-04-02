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