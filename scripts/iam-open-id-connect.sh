THUMBPRINT=$(curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq -r '.jwks_uri' | xargs curl -s | openssl x509 -fingerprint -sha1 -noout | sed 's/://g' | awk -F= '{print tolower($2)}')

echo $THUMBPRINT

aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list a031c46782e6e6c662c2c87c76da9aa62ccabd8e