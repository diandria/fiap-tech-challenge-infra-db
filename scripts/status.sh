#!/usr/bin/env bash
#
# Shows everything currently billing in the account, with a daily estimate.
#
# Read-only. Answers "did I leave something running?" before closing the day.
# Scans the whole account, not only what this repository creates: what escapes
# is usually what Terraform does not manage.
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
TOTAL_HOUR=0

say()  { printf '%s\n' "$*"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$*"; }

add_cost() { TOTAL_HOUR=$(awk -v a="$TOTAL_HOUR" -v b="$1" -v n="$2" 'BEGIN{printf "%.4f", a + (b*n)}'); }

require_aws() {
  command -v aws >/dev/null 2>&1 || { say "aws CLI not found."; exit 1; }
  aws sts get-caller-identity >/dev/null 2>&1 || {
    say "AWS credential invalid or expired."
    say "In the Learner Lab: Start Lab > AWS Details > AWS CLI > Show, then paste into ~/.aws/credentials"
    exit 1
  }
}

require_aws

head2 "RDS"
rds=$(aws rds describe-db-instances --region "$REGION" \
  --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,AllocatedStorage]' \
  --output text 2>/dev/null)
if [ -n "$rds" ]; then
  say "$rds" | while read -r id class status storage; do
    say "  $id  $class  $status  ${storage}GB"
  done
  n=$(say "$rds" | grep -c .)
  add_cost 0.018 "$n"
else
  say "  none"
fi

head2 "Running EC2"
ec2=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType]' --output text 2>/dev/null)
if [ -n "$ec2" ]; then
  say "$ec2" | sed 's/^/  /'
  n=$(say "$ec2" | grep -c .)
  add_cost 0.0416 "$n"
else
  say "  none running"
fi

head2 "EKS clusters"
eks=$(aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text 2>/dev/null)
if [ -n "$eks" ]; then
  for c in $eks; do say "  $c"; done
  n=$(printf '%s\n' $eks | grep -c .)
  add_cost 0.10 "$n"
else
  say "  none"
fi

head2 "Load balancers"
elb=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].[LoadBalancerName,Type]' --output text 2>/dev/null)
if [ -n "$elb" ]; then
  say "$elb" | sed 's/^/  /'
  n=$(say "$elb" | grep -c .)
  add_cost 0.0225 "$n"
else
  say "  none"
fi

head2 "NAT gateways"
nat=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null)
if [ -n "$nat" ]; then
  for g in $nat; do say "  $g"; done
  n=$(printf '%s\n' $nat | grep -c .)
  add_cost 0.045 "$n"
else
  say "  none"
fi

head2 "Idle elastic IPs"
eip=$(aws ec2 describe-addresses --region "$REGION" \
  --query 'Addresses[?AssociationId==`null`].PublicIp' --output text 2>/dev/null)
if [ -n "$eip" ]; then
  for i in $eip; do say "  $i  (unassociated, billing)"; done
  n=$(printf '%s\n' $eip | grep -c .)
  add_cost 0.005 "$n"
else
  say "  none"
fi

head2 "Orphaned EBS volumes"
ebs=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].[VolumeId,Size]' --output text 2>/dev/null)
if [ -n "$ebs" ]; then
  say "$ebs" | sed 's/^/  /'
else
  say "  none"
fi

DAY=$(awk -v h="$TOTAL_HOUR" 'BEGIN{printf "%.2f", h*24}')
MONTH=$(awk -v h="$TOTAL_HOUR" 'BEGIN{printf "%.2f", h*730}')

head2 "Estimate"
say "  per hour   ~ USD $TOTAL_HOUR"
say "  per day    ~ USD $DAY"
say "  per month  ~ USD $MONTH"
say ""
say "  Approximate on-demand us-east-1 list prices, excluding storage and traffic."
say "  Good for order of magnitude, not for reconciling an invoice."

if [ "$(awk -v h="$TOTAL_HOUR" 'BEGIN{print (h>0)?1:0}')" = "1" ]; then
  say ""
  say "  Resources are billing. To tear down: ./scripts/teardown.sh"
fi
