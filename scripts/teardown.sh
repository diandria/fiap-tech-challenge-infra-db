#!/usr/bin/env bash
#
# Derruba a infraestrutura provisionada por este repositorio.
#
#   ./scripts/teardown.sh                    destroy do Terraform + conferencia
#   ./scripts/teardown.sh --sweep            remove tambem o que sobrou fora do estado
#   ./scripts/teardown.sh --include-backend  remove tambem o bucket de estado
#   ./scripts/teardown.sh --yes              nao pergunta (para uso em workflow)
#
# Por que existe o --sweep: se o estado se perder ou dessincronizar, o
# `terraform destroy` nao encontra os recursos, mas a AWS continua cobrando por
# eles. O sweep procura pelo recurso na conta, nao no estado.
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
DB_IDENTIFIER="${DB_IDENTIFIER:-car-repair-shop-db}"
# Nome do bucket resolvido depois da checagem de credencial: ele leva o ID da
# conta como sufixo, porque o namespace de bucket do S3 e global.
BUCKET="${TF_STATE_BUCKET:-}"

SWEEP=false; INCLUDE_BACKEND=false; ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --sweep)           SWEEP=true ;;
    --include-backend) INCLUDE_BACKEND=true ;;
    --yes|-y)          ASSUME_YES=true ;;
    -h|--help)         awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "Opcao desconhecida: $arg"; exit 1 ;;
  esac
done

cd "$(dirname "$0")/.."

fail() { echo "ERRO: $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || fail "aws CLI nao encontrado."
aws sts get-caller-identity >/dev/null 2>&1 || fail \
  "Credencial AWS invalida ou expirada. No Learner Lab: Start Lab > AWS Details > AWS CLI > Show."

if [ -z "$BUCKET" ]; then
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  BUCKET="fiap-tech-challenge-tfstate-${ACCOUNT_ID}"
fi

confirm() {
  $ASSUME_YES && return 0
  printf '%s ' "$1"
  read -r reply
  [ "$reply" = "sim" ] || { echo "Cancelado."; exit 0; }
}

echo "== 1. terraform destroy =="
if [ -d .terraform ] || terraform init -input=false >/dev/null 2>&1; then
  confirm "Destruir a infraestrutura de $REGION? Digite 'sim' para confirmar:"
  terraform destroy -auto-approve || echo "  destroy retornou erro; o sweep abaixo cobre o que sobrou"
else
  echo "  Terraform nao inicializado; pulando para a verificacao"
fi

echo
echo "== 2. conferindo o que sobrou =="
leftover=0

rds=$(aws rds describe-db-instances --region "$REGION" \
  --query "DBInstances[].DBInstanceIdentifier" --output text 2>/dev/null)
if [ -n "$rds" ]; then
  echo "  RDS ainda presente: $rds"
  leftover=1
else
  echo "  RDS: limpo"
fi

sg=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${DB_IDENTIFIER}" \
  --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)
[ -n "$sg" ] && { echo "  Security group ainda presente: $sg"; leftover=1; } || echo "  Security group: limpo"

sng=$(aws rds describe-db-subnet-groups --region "$REGION" \
  --query "DBSubnetGroups[?DBSubnetGroupName=='${DB_IDENTIFIER}'].DBSubnetGroupName" \
  --output text 2>/dev/null)
[ -n "$sng" ] && { echo "  Subnet group ainda presente: $sng"; leftover=1; } || echo "  Subnet group: limpo"

if [ "$leftover" = "1" ] && [ "$SWEEP" = "true" ]; then
  echo
  echo "== 3. sweep: removendo o que o estado nao alcancou =="
  confirm "O sweep apaga recursos direto na AWS, sem passar pelo estado. Digite 'sim':"

  if [ -n "$rds" ]; then
    for id in $rds; do
      echo "  removendo instancia $id"
      aws rds delete-db-instance --region "$REGION" --db-instance-identifier "$id" \
        --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 \
        && echo "    delete disparado" || echo "    falhou; ver console"
    done
    echo "  aguardando a instancia sumir (pode levar minutos)..."
    for id in $rds; do
      aws rds wait db-instance-deleted --region "$REGION" --db-instance-identifier "$id" 2>/dev/null \
        && echo "    $id removida"
    done
  fi

  # O subnet group so aceita remocao depois que a instancia sai.
  [ -n "$sng" ] && aws rds delete-db-subnet-group --region "$REGION" \
    --db-subnet-group-name "$sng" >/dev/null 2>&1 && echo "  subnet group removido"
  [ -n "$sg" ] && aws ec2 delete-security-group --region "$REGION" \
    --group-id "$sg" >/dev/null 2>&1 && echo "  security group removido"
elif [ "$leftover" = "1" ]; then
  echo
  echo "  Sobrou recurso. Rode novamente com --sweep para remover direto na AWS."
fi

if [ "$INCLUDE_BACKEND" = "true" ]; then
  echo
  echo "== 4. removendo o backend de estado =="
  echo "  Isto apaga o historico do estado. So faz sentido ao encerrar o projeto."
  echo "  Bucket: $BUCKET"
  confirm "Apagar o bucket $BUCKET? Digite 'sim':"

  # Bucket versionado nao aceita remocao com versoes dentro, e a trava nativa
  # deixa objetos .tflock que tambem contam. Apagar tudo em lotes primeiro.
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
    && echo "  bucket removido" || echo "  bucket nao removido (ja inexistente ou ainda com objetos)"
fi

echo
echo "== fim =="
echo "Para conferir se algo ainda cobra na conta: ./scripts/status.sh"
