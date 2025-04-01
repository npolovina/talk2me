# Get the source role name
SOURCE_ROLE="github-actions-talk2me-role "

# Get the destination role name
DESTINATION_ROLE="GitHub-Actions-User "

# List all policies attached to the source role
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $SOURCE_ROLE --query 'AttachedPolicies[*].PolicyArn' --output text)

# Attach each policy to the destination role
for POLICY_ARN in $ATTACHED_POLICIES; do
  echo "Attaching policy $POLICY_ARN to $DESTINATION_ROLE"
  aws iam attach-role-policy --role-name $DESTINATION_ROLE --policy-arn $POLICY_ARN
done