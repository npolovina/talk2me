# Run this from your local machine with admin credentials
export ROLE_ARN="arn:aws:iam::637423575947:role/github-actions-talk2me-role"
export EKS_CLUSTER_NAME="talk2me-cluster"  # Replace with your actual cluster name
export AWS_REGION="us-east-1"  # Replace with your region

# Update kubeconfig
aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION

# Use eksctl to update aws-auth
eksctl create iamidentitymapping \
  --cluster $EKS_CLUSTER_NAME \
  --region $AWS_REGION \
  --arn $ROLE_ARN \
  --username github-actions-talk2me-role \
  --group system:masters