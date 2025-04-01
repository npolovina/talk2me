aws iam update-assume-role-policy \
  --role-name github-actions-talk2me-role \
  --policy-document file://trust-policy.json
