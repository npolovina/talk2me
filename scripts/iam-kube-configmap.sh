# Create a patch file
cat << EOF > aws-auth-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - groups:
      - system:masters
      rolearn:rolearn: arn:aws:iam::637423575947:user/GitHub-Actions-User

      username: github-actions-***-role
EOF

# Apply with kubectl
kubectl patch configmap/aws-auth -n kube-system --patch "$(cat iam-kube-configmap.yaml)"