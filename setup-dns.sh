#!/bin/bash
# setup-dns.sh - Automated script to set up DNS, SSL certificates and EKS Ingress for talk2me.com

set -e

# Configuration - Update these variables
DOMAIN="talk2me.com"
API_SUBDOMAIN="api.${DOMAIN}"
EKS_CLUSTER_NAME="talk2me-cluster"
AWS_REGION="us-east-1"
HOSTED_ZONE_ID="Z01708443OKPKB2I0BHFX"  # Your hosted zone ID

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
echo -e "${GREEN}"
echo "███████╗████████╗██╗   ██╗██████╗     ██████╗ ███╗   ██╗███████╗"
echo "██╔════╝╚══██╔══╝██║   ██║██╔══██╗    ██╔══██╗████╗  ██║██╔════╝"
echo "█████╗     ██║   ██║   ██║██████╔╝    ██║  ██║██╔██╗ ██║███████╗"
echo "██╔══╝     ██║   ██║   ██║██╔═══╝     ██║  ██║██║╚██╗██║╚════██║"
echo "███████╗   ██║   ╚██████╔╝██║         ██████╔╝██║ ╚████║███████║"
echo "╚══════╝   ╚═╝    ╚═════╝ ╚═╝         ╚═════╝ ╚═╝  ╚═══╝╚══════╝"
echo -e "${NC}"
echo "DNS and SSL Certificate Setup for ${DOMAIN}"
echo "==========================================================="

# Check for required tools
check_requirements() {
  echo -e "${YELLOW}Checking requirements...${NC}"
  
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it and try again.${NC}"
    exit 1
  fi
  
  # Check for kubectl
  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install it and try again.${NC}"
    exit 1
  fi
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is not installed. Please install it with 'apt-get install jq' or equivalent and try again.${NC}"
    exit 1
  fi
  
  # Check AWS credentials
  if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}AWS credentials not properly configured. Please run 'aws configure' and try again.${NC}"
    exit 1
  fi
  
  # Check EKS cluster
  if ! aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} &> /dev/null; then
    echo -e "${RED}EKS cluster ${EKS_CLUSTER_NAME} not found in region ${AWS_REGION}.${NC}"
    echo -e "${RED}Please check the cluster name and region or create the cluster first.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}All requirements satisfied.${NC}"
}

# Configure kubectl to use the EKS cluster
configure_kubectl() {
  echo -e "${YELLOW}Configuring kubectl to use the EKS cluster...${NC}"
  aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}
  echo -e "${GREEN}kubectl configured successfully.${NC}"
}

# Verify the hosted zone exists
verify_hosted_zone() {
  echo -e "${YELLOW}Verifying Route53 hosted zone...${NC}"
  
  if ! aws route53 get-hosted-zone --id ${HOSTED_ZONE_ID} &> /dev/null; then
    echo -e "${RED}Hosted zone ID ${HOSTED_ZONE_ID} not found.${NC}"
    echo -e "${RED}Please check the ID or create a hosted zone first.${NC}"
    exit 1
  fi
  
  ZONE_DOMAIN=$(aws route53 get-hosted-zone --id ${HOSTED_ZONE_ID} | jq -r '.HostedZone.Name' | sed 's/\.$//')
  
  if [[ "${ZONE_DOMAIN}" != "${DOMAIN}" ]]; then
    echo -e "${YELLOW}Warning: Hosted zone domain (${ZONE_DOMAIN}) does not match configured domain (${DOMAIN}).${NC}"
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${RED}Exiting.${NC}"
      exit 1
    fi
  fi
  
  echo -e "${GREEN}Hosted zone verified.${NC}"
}

# Request an ACM certificate
request_certificate() {
  echo -e "${YELLOW}Requesting ACM certificate for ${DOMAIN} and *.${DOMAIN}...${NC}"
  
  # Check if certificate already exists
  EXISTING_CERT=$(aws acm list-certificates --region ${AWS_REGION} | jq -r ".CertificateSummaryList[] | select(.DomainName == \"${DOMAIN}\") | .CertificateArn")
  
  if [[ -n ${EXISTING_CERT} ]]; then
    echo -e "${YELLOW}Certificate for ${DOMAIN} already exists with ARN: ${EXISTING_CERT}${NC}"
    read -p "Do you want to use this existing certificate? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      CERTIFICATE_ARN=${EXISTING_CERT}
      echo -e "${GREEN}Using existing certificate.${NC}"
      return
    fi
  fi
  
  # Request new certificate
  CERTIFICATE_ARN=$(aws acm request-certificate \
    --domain-names ${DOMAIN},*.${DOMAIN} \
    --validation-method DNS \
    --region ${AWS_REGION} \
    --output text)
  
  echo -e "${GREEN}Certificate requested successfully with ARN: ${CERTIFICATE_ARN}${NC}"
  
  # Wait for certificate details to be available
  echo -e "${YELLOW}Waiting for certificate details to be available...${NC}"
  sleep 10
}

# Add DNS validation records
add_validation_records() {
  echo -e "${YELLOW}Adding DNS validation records...${NC}"
  
  # Get certificate details
  CERT_DETAILS=$(aws acm describe-certificate \
    --certificate-arn ${CERTIFICATE_ARN} \
    --region ${AWS_REGION})
  
  # Extract validation records
  echo -e "${YELLOW}Extracting validation records...${NC}"
  
  # Create a temporary validation records file
  TEMP_FILE=$(mktemp)
  
  echo "{" > ${TEMP_FILE}
  echo "  \"Changes\": [" >> ${TEMP_FILE}
  
  # Process all domain validation records
  RECORD_COUNT=$(echo ${CERT_DETAILS} | jq '.Certificate.DomainValidationOptions | length')
  
  for (( i=0; i<${RECORD_COUNT}; i++ )); do
    VALIDATION_NAME=$(echo ${CERT_DETAILS} | jq -r ".Certificate.DomainValidationOptions[${i}].ResourceRecord.Name")
    VALIDATION_VALUE=$(echo ${CERT_DETAILS} | jq -r ".Certificate.DomainValidationOptions[${i}].ResourceRecord.Value")
    
    echo "    {" >> ${TEMP_FILE}
    echo "      \"Action\": \"UPSERT\"," >> ${TEMP_FILE}
    echo "      \"ResourceRecordSet\": {" >> ${TEMP_FILE}
    echo "        \"Name\": \"${VALIDATION_NAME}\"," >> ${TEMP_FILE}
    echo "        \"Type\": \"CNAME\"," >> ${TEMP_FILE}
    echo "        \"TTL\": 300," >> ${TEMP_FILE}
    echo "        \"ResourceRecords\": [" >> ${TEMP_FILE}
    echo "          {" >> ${TEMP_FILE}
    echo "            \"Value\": \"${VALIDATION_VALUE}\"" >> ${TEMP_FILE}
    echo "          }" >> ${TEMP_FILE}
    echo "        ]" >> ${TEMP_FILE}
    echo "      }" >> ${TEMP_FILE}
    
    # Add comma if not the last record
    if [[ $i -lt $((RECORD_COUNT-1)) ]]; then
      echo "    }," >> ${TEMP_FILE}
    else
      echo "    }" >> ${TEMP_FILE}
    fi
  done
  
  echo "  ]" >> ${TEMP_FILE}
  echo "}" >> ${TEMP_FILE}
  
  # Apply the validation records
  echo -e "${YELLOW}Applying validation records to Route53...${NC}"
  aws route53 change-resource-record-sets \
    --hosted-zone-id ${HOSTED_ZONE_ID} \
    --change-batch file://${TEMP_FILE}
  
  rm ${TEMP_FILE}
  
  echo -e "${GREEN}Validation records added successfully.${NC}"
}

# Wait for certificate validation
wait_for_certificate() {
  echo -e "${YELLOW}Waiting for certificate validation (this may take several minutes)...${NC}"
  
  while true; do
    STATUS=$(aws acm describe-certificate \
      --certificate-arn ${CERTIFICATE_ARN} \
      --region ${AWS_REGION} \
      --query 'Certificate.Status' \
      --output text)
    
    if [[ ${STATUS} == "ISSUED" ]]; then
      echo -e "${GREEN}Certificate validated and issued successfully.${NC}"
      break
    elif [[ ${STATUS} == "FAILED" ]]; then
      echo -e "${RED}Certificate validation failed. Please check AWS ACM console for details.${NC}"
      exit 1
    else
      echo -e "${YELLOW}Current status: ${STATUS}. Waiting 30 seconds...${NC}"
      sleep 30
    fi
  done
}

# Install AWS Load Balancer Controller if not already installed
install_alb_controller() {
  echo -e "${YELLOW}Checking if AWS Load Balancer Controller is installed...${NC}"
  
  if kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
    echo -e "${GREEN}AWS Load Balancer Controller is already installed.${NC}"
  else
    echo -e "${YELLOW}Installing AWS Load Balancer Controller...${NC}"
    
    # Create IAM policy for the AWS Load Balancer Controller
    POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
    POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)
    
    if [[ -z "${POLICY_ARN}" ]]; then
      echo -e "${YELLOW}Creating IAM policy for AWS Load Balancer Controller...${NC}"
      curl -o alb-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
      
      POLICY_ARN=$(aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document file://alb-policy.json \
        --query 'Policy.Arn' --output text)
      
      rm alb-policy.json
    else
      echo -e "${GREEN}IAM policy ${POLICY_NAME} already exists.${NC}"
    fi
    
    # Create service account for the AWS Load Balancer Controller
    echo -e "${YELLOW}Creating service account for AWS Load Balancer Controller...${NC}"
    eksctl create iamserviceaccount \
      --cluster=${EKS_CLUSTER_NAME} \
      --namespace=kube-system \
      --name=aws-load-balancer-controller \
      --attach-policy-arn=${POLICY_ARN} \
      --override-existing-serviceaccounts \
      --approve \
      --region ${AWS_REGION}
    
    # Install AWS Load Balancer Controller using Helm
    echo -e "${YELLOW}Installing AWS Load Balancer Controller using Helm...${NC}"
    
    # Add Helm repo
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    # Install the AWS Load Balancer Controller
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      --set clusterName=${EKS_CLUSTER_NAME} \
      --set serviceAccount.create=false \
      --set serviceAccount.name=aws-load-balancer-controller
    
    echo -e "${GREEN}AWS Load Balancer Controller installed successfully.${NC}"
  fi
}

# Install ExternalDNS
install_external_dns() {
  echo -e "${YELLOW}Checking if ExternalDNS is installed...${NC}"
  
  if kubectl get deployment -n kube-system external-dns &> /dev/null; then
    echo -e "${GREEN}ExternalDNS is already installed.${NC}"
  else
    echo -e "${YELLOW}Installing ExternalDNS...${NC}"
    
    # Create IAM policy for ExternalDNS
    POLICY_NAME="ExternalDNSPolicy"
    POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)
    
    if [[ -z "${POLICY_ARN}" ]]; then
      echo -e "${YELLOW}Creating IAM policy for ExternalDNS...${NC}"
      
      # Create policy document
      cat > external-dns-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
      
      POLICY_ARN=$(aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document file://external-dns-policy.json \
        --query 'Policy.Arn' --output text)
      
      rm external-dns-policy.json
    else
      echo -e "${GREEN}IAM policy ${POLICY_NAME} already exists.${NC}"
    fi
    
    # Create service account for ExternalDNS
    echo -e "${YELLOW}Creating service account for ExternalDNS...${NC}"
    eksctl create iamserviceaccount \
      --cluster=${EKS_CLUSTER_NAME} \
      --namespace=kube-system \
      --name=external-dns \
      --attach-policy-arn=${POLICY_ARN} \
      --override-existing-serviceaccounts \
      --approve \
      --region ${AWS_REGION}
    
    # Deploy ExternalDNS
    echo -e "${YELLOW}Deploying ExternalDNS...${NC}"
    
    # Create ExternalDNS deployment YAML
    cat > external-dns.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: $(aws iam get-role --role-name eksctl-${EKS_CLUSTER_NAME}-addon-iamserviceaccount-kube-system-external-dns-Role1 --query 'Role.Arn' --output text)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: k8s.gcr.io/external-dns/external-dns:v0.10.2
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=${DOMAIN}
        - --provider=aws
        - --aws-zone-type=public
        - --registry=txt
        - --txt-owner-id=${HOSTED_ZONE_ID}
      securityContext:
        fsGroup: 65534
EOF
    
    kubectl apply -f external-dns.yaml
    rm external-dns.yaml
    
    echo -e "${GREEN}ExternalDNS installed successfully.${NC}"
  fi
}

# Update ingress YAML with certificate ARN
update_ingress() {
  echo -e "${YELLOW}Updating ingress YAML with certificate ARN...${NC}"
  
  # Create updated ingress file
  cat > ingress-updated.yaml << EOF
# Updated ingress.yaml with SSL certificate
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: talk2me-ingress
  namespace: talk2me
  annotations:
    kubernetes.io/ingress.class: "alb"
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: "${CERTIFICATE_ARN}"
    alb.ingress.kubernetes.io/ssl-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"
    external-dns.alpha.kubernetes.io/hostname: "${DOMAIN},${API_SUBDOMAIN}"
spec:
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: talk2me-frontend
            port:
              number: 80
  - host: ${API_SUBDOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: talk2me-backend
            port:
              number: 80
EOF
  
  echo -e "${GREEN}Ingress YAML updated successfully.${NC}"
  
  # Apply the ingress
  echo -e "${YELLOW}Applying ingress to the cluster...${NC}"
  kubectl apply -f ingress-updated.yaml
  
  # Optionally save the file for future reference
  cp ingress-updated.yaml k8s/ingress.yaml
  
  echo -e "${GREEN}Ingress applied successfully.${NC}"
}

# Main execution flow
main() {
  check_requirements
  configure_kubectl
  verify_hosted_zone
  request_certificate
  add_validation_records
  wait_for_certificate
  install_alb_controller
  install_external_dns
  update_ingress
  
  echo -e "${GREEN}"
  echo "======================================================================"
  echo " DNS and SSL Certificate Setup Complete for ${DOMAIN}"
  echo "======================================================================"
  echo -e "${NC}"
  echo "Summary:"
  echo "- Certificate ARN: ${CERTIFICATE_ARN}"
  echo "- Domain Names: ${DOMAIN}, *.${DOMAIN}"
  echo "- Application URL: https://${DOMAIN}"
  echo "- API URL: https://${API_SUBDOMAIN}"
  echo
  echo "Next steps:"
  echo "1. Verify DNS propagation: 'dig ${DOMAIN}' (may take a few minutes)"
  echo "2. Check ingress status: 'kubectl get ingress -n talk2me'"
  echo "3. Monitor application deployment: 'kubectl get pods -n talk2me'"
  echo
  echo "The deployment details are stored in 'k8s/ingress.yaml' for future reference."
  echo -e "${NC}"
}

# Execute the main function
main