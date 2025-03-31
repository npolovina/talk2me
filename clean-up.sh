#!/bin/bash
# cleanup-dns.sh - Script to remove all DNS and Route 53 resources for talk2me.com

set -e

# Configuration - Update these variables
DOMAIN="talk2me.com"
API_SUBDOMAIN="api.${DOMAIN}"
EKS_CLUSTER_NAME="talk2me-cluster"
AWS_REGION="us-east-1"
HOSTED_ZONE_ID="Z01720181WBWPKXMFDZK"  # Your hosted zone ID

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Banner
echo -e "${RED}"
echo "██████╗ ███╗   ██╗███████╗     ██████╗██╗     ███████╗ █████╗ ███╗   ██╗██╗   ██╗██████╗"
echo "██╔══██╗████╗  ██║██╔════╝    ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║██║   ██║██╔══██╗"
echo "██║  ██║██╔██╗ ██║███████╗    ██║     ██║     █████╗  ███████║██╔██╗ ██║██║   ██║██████╔╝"
echo "██║  ██║██║╚██╗██║╚════██║    ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║██║   ██║██╔═══╝"
echo "██████╔╝██║ ╚████║███████║    ╚██████╗███████╗███████╗██║  ██║██║ ╚████║╚██████╔╝██║"
echo "╚═════╝ ╚═╝  ╚═══╝╚══════╝     ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝"
echo -e "${NC}"
echo "DNS and Route 53 Resource Cleanup for ${DOMAIN}"
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
  
  echo -e "${GREEN}All requirements satisfied.${NC}"
}

# Configure kubectl to use the EKS cluster
configure_kubectl() {
  echo -e "${YELLOW}Configuring kubectl to use the EKS cluster...${NC}"
  
  if aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} &> /dev/null; then
    aws eks update-kubeconfig --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION}
    echo -e "${GREEN}kubectl configured successfully.${NC}"
  else
    echo -e "${YELLOW}EKS cluster ${EKS_CLUSTER_NAME} not found. Skipping kubectl configuration.${NC}"
  fi
}

# Remove Ingress resource
remove_ingress() {
  echo -e "${YELLOW}Removing ingress resources...${NC}"
  
  if kubectl get ingress talk2me-ingress -n talk2me &> /dev/null; then
    kubectl delete ingress talk2me-ingress -n talk2me
    echo -e "${GREEN}Ingress removed successfully.${NC}"
  else
    echo -e "${YELLOW}Ingress not found. Skipping.${NC}"
  fi
  
  # Give AWS ALB Controller time to delete the ALB
  echo -e "${YELLOW}Waiting for ALB to be deleted (30 seconds)...${NC}"
  sleep 30
}

# Remove ExternalDNS
remove_external_dns() {
  echo -e "${YELLOW}Removing ExternalDNS...${NC}"
  
  if kubectl get deployment -n kube-system external-dns &> /dev/null; then
    kubectl delete deployment -n kube-system external-dns
    kubectl delete clusterrole external-dns --ignore-not-found
    kubectl delete clusterrolebinding external-dns-viewer --ignore-not-found
    echo -e "${GREEN}ExternalDNS deployment removed.${NC}"
  else
    echo -e "${YELLOW}ExternalDNS deployment not found. Skipping.${NC}"
  fi
  
  # Clean up the IAM service account
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  SERVICE_ACCOUNT_ROLE="eksctl-${EKS_CLUSTER_NAME}-addon-iamserviceaccount-kube-system-external-dns-Role1"
  
  if aws iam get-role --role-name ${SERVICE_ACCOUNT_ROLE} &> /dev/null; then
    echo -e "${YELLOW}Removing IAM role for ExternalDNS...${NC}"
    
    # Detach policies from the role
    for policy in $(aws iam list-attached-role-policies --role-name ${SERVICE_ACCOUNT_ROLE} --query "AttachedPolicies[].PolicyArn" --output text); do
      aws iam detach-role-policy --role-name ${SERVICE_ACCOUNT_ROLE} --policy-arn ${policy}
    done
    
    # Delete the role
    aws iam delete-role --role-name ${SERVICE_ACCOUNT_ROLE}
    echo -e "${GREEN}IAM role for ExternalDNS removed.${NC}"
  else
    echo -e "${YELLOW}IAM role for ExternalDNS not found. Skipping.${NC}"
  fi
  
  # Clean up the service account
  if kubectl get serviceaccount -n kube-system external-dns &> /dev/null; then
    kubectl delete serviceaccount -n kube-system external-dns
    echo -e "${GREEN}Kubernetes service account for ExternalDNS removed.${NC}"
  fi
  
  # Delete ExternalDNS policy
  POLICY_NAME="ExternalDNSPolicy"
  POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" --output text)
  
  if [[ -n "${POLICY_ARN}" ]]; then
    echo -e "${YELLOW}Removing IAM policy ${POLICY_NAME}...${NC}"
    aws iam delete-policy --policy-arn ${POLICY_ARN}
    echo -e "${GREEN}IAM policy ${POLICY_NAME} removed.${NC}"
  else
    echo -e "${YELLOW}IAM policy ${POLICY_NAME} not found. Skipping.${NC}"
  fi
}

# Remove DNS records for the domain in Route 53
remove_dns_records() {
  echo -e "${YELLOW}Removing DNS records for ${DOMAIN} and ${API_SUBDOMAIN}...${NC}"
  
  # Get all the records for the domain
  RECORDS=$(aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID})
  
  # Filter for records for our domain (excluding NS and SOA records which should be kept)
  DOMAIN_RECORDS=$(echo ${RECORDS} | jq '.ResourceRecordSets[] | select((.Name | contains("'${DOMAIN}'")) and (.Type != "NS") and (.Type != "SOA"))')
  
  if [[ -n "${DOMAIN_RECORDS}" ]]; then
    # Create a temporary file for the change batch
    TEMP_FILE=$(mktemp)
    
    echo "{" > ${TEMP_FILE}
    echo "  \"Changes\": [" >> ${TEMP_FILE}
    
    # Process each record
    FIRST=true
    
    echo ${RECORDS} | jq -c '.ResourceRecordSets[] | select((.Name | contains("'${DOMAIN}'")) and (.Type != "NS") and (.Type != "SOA"))' | while read -r record; do
      NAME=$(echo ${record} | jq -r '.Name')
      TYPE=$(echo ${record} | jq -r '.Type')
      
      echo -e "${YELLOW}Processing record: ${NAME} (${TYPE})${NC}"
      
      # Add comma for all but the first record
      if [[ ${FIRST} == true ]]; then
        FIRST=false
      else
        echo "    }," >> ${TEMP_FILE}
      fi
      
      # Add the delete action
      echo "    {" >> ${TEMP_FILE}
      echo "      \"Action\": \"DELETE\"," >> ${TEMP_FILE}
      echo "      \"ResourceRecordSet\": ${record}" >> ${TEMP_FILE}
    done
    
    # Close the JSON
    echo "    }" >> ${TEMP_FILE}
    echo "  ]" >> ${TEMP_FILE}
    echo "}" >> ${TEMP_FILE}
    
    # Apply the changes
    echo -e "${YELLOW}Deleting DNS records...${NC}"
    aws route53 change-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --change-batch file://${TEMP_FILE}
    
    rm ${TEMP_FILE}
    echo -e "${GREEN}DNS records removed successfully.${NC}"
  else
    echo -e "${YELLOW}No matching DNS records found to remove.${NC}"
  fi
}

# Delete ACM certificate
delete_certificate() {
  echo -e "${YELLOW}Finding and deleting ACM certificate for ${DOMAIN}...${NC}"
  
  # Find certificate for the domain
  CERTIFICATE_ARN=$(aws acm list-certificates --region ${AWS_REGION} | jq -r ".CertificateSummaryList[] | select(.DomainName == \"${DOMAIN}\") | .CertificateArn")
  
  if [[ -n "${CERTIFICATE_ARN}" ]]; then
    echo -e "${YELLOW}Found certificate: ${CERTIFICATE_ARN}${NC}"
    
    # Check if certificate is in use
    CERT_IN_USE=$(aws acm describe-certificate --certificate-arn ${CERTIFICATE_ARN} --region ${AWS_REGION} | jq -r '.Certificate.InUseBy | length')
    
    if [[ ${CERT_IN_USE} -gt 0 ]]; then
      echo -e "${RED}Certificate is still in use. Please remove all resources using this certificate first.${NC}"
      echo -e "${RED}Resources using this certificate:${NC}"
      aws acm describe-certificate --certificate-arn ${CERTIFICATE_ARN} --region ${AWS_REGION} | jq -r '.Certificate.InUseBy[]'
    else
      echo -e "${YELLOW}Deleting certificate...${NC}"
      aws acm delete-certificate --certificate-arn ${CERTIFICATE_ARN} --region ${AWS_REGION}
      echo -e "${GREEN}Certificate deleted successfully.${NC}"
    fi
  else
    echo -e "${YELLOW}No certificate found for ${DOMAIN}. Skipping.${NC}"
  fi
}

# Delete hosted zone if requested
delete_hosted_zone() {
  echo -e "${YELLOW}Checking Route 53 hosted zone...${NC}"
  
  if aws route53 get-hosted-zone --id ${HOSTED_ZONE_ID} &> /dev/null; then
    echo -e "${YELLOW}Found hosted zone: ${HOSTED_ZONE_ID}${NC}"
    
    read -p "Do you want to delete the entire hosted zone for ${DOMAIN}? (y/n) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # Check for remaining records
      RECORDS_COUNT=$(aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} | jq '.ResourceRecordSets | length')
      
      if [[ ${RECORDS_COUNT} -gt 2 ]]; then # 2 because there's always NS and SOA records
        echo -e "${RED}Hosted zone still has DNS records. Please remove them first.${NC}"
        echo -e "${YELLOW}You can run this script again with the --force flag to skip this check.${NC}"
        
        if [[ "$1" == "--force" ]]; then
          echo -e "${YELLOW}Force flag detected. Proceeding with deletion...${NC}"
        else
          return
        fi
      fi
      
      echo -e "${YELLOW}Deleting hosted zone...${NC}"
      aws route53 delete-hosted-zone --id ${HOSTED_ZONE_ID}
      echo -e "${GREEN}Hosted zone deleted successfully.${NC}"
    else
      echo -e "${YELLOW}Skipping hosted zone deletion.${NC}"
    fi
  else
    echo -e "${YELLOW}Hosted zone ${HOSTED_ZONE_ID} not found. Skipping.${NC}"
  fi
}

# Main execution flow
main() {
  echo -e "${YELLOW}Starting cleanup of DNS resources for ${DOMAIN}...${NC}"
  echo
  echo -e "${RED}WARNING: This will remove DNS records, certificates, and related resources.${NC}"
  echo -e "${RED}This action is IRREVERSIBLE. Make sure you have backups if needed.${NC}"
  echo
  
  read -p "Are you sure you want to proceed? (y/n) " -n 1 -r
  echo
  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
  fi
  
  check_requirements
  configure_kubectl
  remove_ingress
  remove_external_dns
  remove_dns_records
  delete_certificate
  
  # Ask if user wants to delete hosted zone
  if [[ "$1" == "--delete-zone" || "$1" == "--force" ]]; then
    delete_hosted_zone "$1"
  fi
  
  echo -e "${GREEN}"
  echo "======================================================================"
  echo " DNS Resource Cleanup Complete for ${DOMAIN}"
  echo "======================================================================"
  echo -e "${NC}"
  echo "Summary of removed resources:"
  echo "- Kubernetes ingress resources"
  echo "- ExternalDNS deployment and IAM resources"
  echo "- DNS records for ${DOMAIN} and ${API_SUBDOMAIN}"
  echo "- ACM certificate (if not in use)"
  
  if [[ "$1" == "--delete-zone" || "$1" == "--force" ]]; then
    echo "- Route 53 hosted zone (if confirmed)"
  fi
  
  echo
  echo "Note: If there were resources still in use, some deletions may have been skipped."
  echo "Run this script with '--force' to attempt more aggressive cleanup."
  echo -e "${NC}"
}

# Execute the main function with any passed arguments
main "$@"