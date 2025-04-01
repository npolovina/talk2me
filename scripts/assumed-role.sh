# Get your EKS cluster name
CLUSTER_NAME="talk2me"  # Replace with your actual cluster name
REGION="us-east-1"  # Replace with your region

# Get the full ARN of your GitHub Actions role
ROLE_ARN="arn:aws:iam::637423575947:role/github-actions-talk2me-role"

# Update kubeconfig
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# Add the role to aws-auth ConfigMap
eksctl create iamidentitymapping \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --arn $ROLE_ARN \
  --username github-actions-talk2me-role \
  --group system:masters

# Verify the update
kubectl describe configmap -n kube-system aws-auth