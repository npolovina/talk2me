
#!/bin/bash
# Run this script locally to update the aws-auth ConfigMap

# Set your variables
CLUSTER_NAME="talk2me"
REGION="us-east-1"
GITHUB_ACTIONS_ROLE_ARN="arn:aws:iam::637423575947:role/github-actions-talk2me-role"

# Update kubeconfig
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Use eksctl to add the role mapping
eksctl create iamidentitymapping \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --arn $GITHUB_ACTIONS_ROLE_ARN \
  --username github-actions \
  --group system:masters

# Verify the update
kubectl describe configmap -n kube-system aws-auth