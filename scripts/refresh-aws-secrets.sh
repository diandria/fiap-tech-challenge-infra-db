#!/usr/bin/env bash
#
# Copia a credencial local do Learner Lab para os secrets do GitHub Actions.
#
#   ./scripts/refresh-aws-secrets.sh
#
# A credencial do Learner Lab expira em cerca de 4 horas, e o CI para de
# conseguir rodar o plan quando isso acontece. Este script existe para que
# renovar seja um comando, e nao tres edicoes manuais na interface do GitHub.
#
# Antes de rodar: Start Lab > AWS Details > AWS CLI > Show, e cole o bloco em
# ~/.aws/credentials.
set -uo pipefail

CRED_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
PROFILE="${AWS_PROFILE:-default}"

fail() { echo "ERRO: $*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || fail "gh CLI nao encontrado."
gh auth status >/dev/null 2>&1 || fail "gh nao autenticado. Rode: gh auth login"
[ -f "$CRED_FILE" ] || fail "Arquivo de credencial nao encontrado em $CRED_FILE"

# Le uma chave da secao do perfil, sem imprimir o valor.
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

[ -n "$KEY_ID" ] || fail "aws_access_key_id nao encontrado no perfil [$PROFILE]"
[ -n "$SECRET" ]  || fail "aws_secret_access_key nao encontrado no perfil [$PROFILE]"
[ -z "$TOKEN" ] && echo "Aviso: sem aws_session_token. Credencial do Learner Lab costuma ter um."

echo "Validando a credencial antes de publicar..."
AWS_ACCESS_KEY_ID="$KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET" AWS_SESSION_TOKEN="$TOKEN" \
  aws sts get-caller-identity >/dev/null 2>&1 \
  || fail "A credencial local nao autentica. Renove no Learner Lab antes de publicar."
echo "  ok"

echo "Publicando nos secrets do repositorio..."
printf '%s' "$KEY_ID" | gh secret set AWS_ACCESS_KEY_ID     >/dev/null && echo "  AWS_ACCESS_KEY_ID"
printf '%s' "$SECRET" | gh secret set AWS_SECRET_ACCESS_KEY >/dev/null && echo "  AWS_SECRET_ACCESS_KEY"
printf '%s' "$TOKEN"  | gh secret set AWS_SESSION_TOKEN     >/dev/null && echo "  AWS_SESSION_TOKEN"

# As credenciais do banco vem do tfvars local, se existir. Elas nao expiram,
# entao so precisam ser publicadas uma vez.
if [ -f terraform.tfvars ]; then
  USER_V=$(grep -E '^\s*db_username' terraform.tfvars | cut -d'"' -f2)
  PASS_V=$(grep -E '^\s*db_password' terraform.tfvars | cut -d'"' -f2)
  if [ -n "$USER_V" ] && [ -n "$PASS_V" ]; then
    printf '%s' "$USER_V" | gh secret set DB_USERNAME >/dev/null && echo "  DB_USERNAME"
    printf '%s' "$PASS_V" | gh secret set DB_PASSWORD >/dev/null && echo "  DB_PASSWORD"
  fi
fi

echo
echo "Pronto. Os secrets valem enquanto a sessao do lab durar (cerca de 4h)."
