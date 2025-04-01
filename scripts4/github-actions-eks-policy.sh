POLICY_ARN_FROM_PREVIOUS_COMMAND = <replace with your arn>


aws iam create-policy \
  --policy-name GitHubActionsEKSFullAccess \
  --policy-document file://github-actions-eks-policy.json

aws iam attach-role-policy \
  --role-name github-actions-talk2me-role \
  --policy-arn <POLICY_ARN_FROM_PREVIOUS_COMMAND>