# Attach necessary policies for ECR and EKS
aws iam attach-role-policy --role-name github-actions-talk2me-role --policy-arn arn:aws:iam::aws:policy/AmazonElasticContainerRegistryPublicFullAccess
aws iam attach-role-policy --role-name github-actions-talk2me-role --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-user-policy --user-name GitHub-Actions-User --policy-arn arn:aws:iam::aws:policy/IAMReadOnlyAccess