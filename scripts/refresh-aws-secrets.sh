#!/usr/bin/env bash
#
# Copies the local Learner Lab credential into the GitHub Actions secrets.
#
#   ./scripts/refresh-aws-secrets.sh
#
# The Learner Lab credential expires in about 4 hours, and the CI stops being
# able to run the plan when it does. This makes renewal one command instead of
# three manual edits in the GitHub interface.
#
# Before running: Start Lab > AWS Details > AWS CLI > Show, then paste the
# block into ~/.aws/credentials.
set -uo pipefail

CRED_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
PROFILE="${AWS_PROFILE:-default}"

fail() { echo "ERROR: $*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || fail "gh CLI not found."
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated. Run: gh auth login"
[ -f "$CRED_FILE" ] || fail "Credential file not found at $CRED_FILE"

# Reads a key from the profile section without printing the value.
read_key() {
  awk -v profile="[$PROFILE]" -v key="$1" '
    $0 == profile { inside = 1; next }
    /^\[/         { inside = 0 }
    inside && $0 ~ "^[ \t]*" key "[ \t]*=" {
      sub(/^[^=]*=[ \t]*/, ""); gsub(/[ \t\r]+$/, ""); print; exit
    }
  ' "$CRED_FILE"
}

KEY_ID=$(read_key aws_access_key_id)
SECRET=$(read_key aws_secret_access_key)
TOKEN=$(read_key aws_session_token)

[ -n "$KEY_ID" ] || fail "aws_access_key_id not found in profile [$PROFILE]"
[ -n "$SECRET" ]  || fail "aws_secret_access_key not found in profile [$PROFILE]"
[ -z "$TOKEN" ] && echo "Warning: no aws_session_token. Learner Lab credentials usually have one."

echo "Validating the credential before publishing..."
AWS_ACCESS_KEY_ID="$KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET" AWS_SESSION_TOKEN="$TOKEN" \
  aws sts get-caller-identity >/dev/null 2>&1 \
  || fail "The local credential does not authenticate. Renew it in the Learner Lab first."
echo "  ok"

echo "Publishing to the repository secrets..."
printf '%s' "$KEY_ID" | gh secret set AWS_ACCESS_KEY_ID     >/dev/null && echo "  AWS_ACCESS_KEY_ID"
printf '%s' "$SECRET" | gh secret set AWS_SECRET_ACCESS_KEY >/dev/null && echo "  AWS_SECRET_ACCESS_KEY"
printf '%s' "$TOKEN"  | gh secret set AWS_SESSION_TOKEN     >/dev/null && echo "  AWS_SESSION_TOKEN"

# Database credentials come from the local tfvars, if present. They do not
# expire, so they only need publishing once.
if [ -f terraform.tfvars ]; then
  USER_V=$(grep -E '^\s*db_username' terraform.tfvars | cut -d'"' -f2)
  PASS_V=$(grep -E '^\s*db_password' terraform.tfvars | cut -d'"' -f2)
  if [ -n "$USER_V" ] && [ -n "$PASS_V" ]; then
    printf '%s' "$USER_V" | gh secret set DB_USERNAME >/dev/null && echo "  DB_USERNAME"
    printf '%s' "$PASS_V" | gh secret set DB_PASSWORD >/dev/null && echo "  DB_PASSWORD"
  fi
fi

echo
echo "Done. The secrets last as long as the lab session (about 4h)."
