#!/usr/bin/env bash
#
# Tears down the infrastructure provisioned by this repository.
#
#   ./scripts/teardown.sh                    terraform destroy + verification
#   ./scripts/teardown.sh --sweep            also removes what the state missed
#   ./scripts/teardown.sh --include-backend  also removes the state bucket
#   ./scripts/teardown.sh --yes              no prompts (for workflow use)
#
# Why --sweep exists: if the state is lost or drifts, `terraform destroy` does
# not find the resources but AWS keeps billing for them. The sweep looks for
# resources in the account, not in the state.
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
DB_IDENTIFIER="${DB_IDENTIFIER:-car-repair-shop-db}"
# Bucket name resolved after the credential check: it carries the account id
# as a suffix, because the S3 bucket namespace is global.
BUCKET="${TF_STATE_BUCKET:-}"

SWEEP=false; INCLUDE_BACKEND=false; ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --sweep)           SWEEP=true ;;
    --include-backend) INCLUDE_BACKEND=true ;;
    --yes|-y)          ASSUME_YES=true ;;
    -h|--help)         awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

cd "$(dirname "$0")/.."

fail() { echo "ERROR: $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || fail "aws CLI not found."
aws sts get-caller-identity >/dev/null 2>&1 || fail \
  "AWS credential invalid or expired. Learner Lab: Start Lab > AWS Details > AWS CLI > Show."

if [ -z "$BUCKET" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  BUCKET="fiap-tech-challenge-tfstate-${ACCOUNT_ID}"
fi

confirm() {
  $ASSUME_YES && return 0
  printf '%s ' "$1"
  read -r reply
  [ "$reply" = "yes" ] || { echo "Cancelled."; exit 0; }
}

echo "== 1. terraform destroy =="
if [ -d .terraform ] || terraform init -input=false >/dev/null 2>&1; then
  confirm "Destroy the infrastructure in $REGION? Type 'yes' to confirm:"
  terraform destroy -auto-approve || echo "  destroy failed; the sweep below covers what is left"
else
  echo "  Terraform not initialised; skipping to the verification"
fi

echo
echo "== 2. checking what is left =="
leftover=0

rds=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[].DBInstanceIdentifier" --output text 2>/dev/null)
if [ -n "$rds" ]; then
  echo "  RDS still present: $rds"
  leftover=1
else
  echo "  RDS: clean"
fi

sg=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${DB_IDENTIFIER}" \
  --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)
[ -n "$sg" ] && { echo "  Security group still present: $sg"; leftover=1; } || echo "  Security group: clean"

sng=$(aws rds describe-db-subnet-groups --region "$REGION" \
  --query "DBSubnetGroups[?DBSubnetGroupName=='${DB_IDENTIFIER}'].DBSubnetGroupName" \
  --output text 2>/dev/null)
[ -n "$sng" ] && { echo "  Subnet group still present: $sng"; leftover=1; } || echo "  Subnet group: clean"

if [ "$leftover" = "1" ] && [ "$SWEEP" = "true" ]; then
  echo
  echo "== 3. sweep: removing what the state did not reach =="
  confirm "The sweep deletes resources directly in AWS, bypassing the state. Type 'yes':"

  if [ -n "$rds" ]; then
    for id in $rds; do
      echo "  removing instance $id"
      aws rds delete-db-instance --region "$REGION" --db-instance-identifier "$id" \
        --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 \
        && echo "    delete issued" || echo "    failed; check the console"
    done
    echo "  waiting for the instance to disappear (can take minutes)..."
    for id in $rds; do
      aws rds wait db-instance-deleted --region "$REGION" --db-instance-identifier "$id" 2>/dev/null \
        && echo "    $id removed"
    done
  fi

  # The subnet group only accepts deletion after the instance is gone.
  [ -n "$sng" ] && aws rds delete-db-subnet-group --region "$REGION" \
    --db-subnet-group-name "$sng" >/dev/null 2>&1 && echo "  subnet group removed"
  [ -n "$sg" ] && aws ec2 delete-security-group --region "$REGION" \
    --group-id "$sg" >/dev/null 2>&1 && echo "  security group removed"
elif [ "$leftover" = "1" ]; then
  echo
  echo "  Resources left. Run again with --sweep to delete them directly in AWS."
fi

if [ "$INCLUDE_BACKEND" = "true" ]; then
  echo
  echo "== 4. removing the state backend =="
  echo "  This erases the state history. Only makes sense when closing the project."
  echo "  Bucket: $BUCKET"
  confirm "Delete the bucket $BUCKET? Type 'yes':"

  # A versioned bucket refuses deletion while versions remain, and native
  # locking leaves .tflock objects that count too. Delete in batches first.
  for what in Versions DeleteMarkers; do
    aws s3api list-object-versions --bucket "$BUCKET" \
      --query "{Objects: ${what}[].{Key:Key,VersionId:VersionId}}" --output json 2>/dev/null \
      | BUCKET="$BUCKET" python3 -c "
import sys, json, subprocess, os
bucket = os.environ['BUCKET']
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
objs = (d or {}).get('Objects') or []
for i in range(0, len(objs), 1000):
    batch = json.dumps({'Objects': objs[i:i+1000]})
    subprocess.run(['aws','s3api','delete-objects','--bucket',bucket,'--delete',batch],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
" 2>/dev/null
  done
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1 \
    && echo "  bucket removed" || echo "  bucket not removed (already gone or still holding objects)"
fi

echo
echo "== done =="
echo "To check whether anything is still billing: ./scripts/status.sh"
