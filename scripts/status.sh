#!/usr/bin/env bash
#
# Mostra tudo que esta cobrando na conta agora, com estimativa de custo diario.
#
# Somente leitura: nao altera nada. Serve para responder "esqueci algo ligado?"
# antes de fechar o dia. Varre a conta inteira, nao apenas o que este
# repositorio cria, porque o que costuma escapar e justamente o que o Terraform
# nao gerencia.
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
TOTAL_HOUR=0

say()  { printf '%s\n' "$*"; }
head2() { printf '\n\033[1m%s\033[0m\n' "$*"; }

add_cost() { TOTAL_HOUR=$(awk -v a="$TOTAL_HOUR" -v b="$1" -v n="$2" 'BEGIN{printf "%.4f", a + (b*n)}'); }

require_aws() {
  command -v aws >/dev/null 2>&1 || { say "aws CLI nao encontrado."; exit 1; }
  aws sts get-caller-identity >/dev/null 2>&1 || {
    say "Credencial AWS invalida ou expirada."
    say "No Learner Lab: Start Lab > AWS Details > AWS CLI > Show, e recole em ~/.aws/credentials"
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
  say "  nenhuma instancia"
fi

head2 "EC2 em execucao"
ec2=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType]' --output text 2>/dev/null)
if [ -n "$ec2" ]; then
  say "$ec2" | sed 's/^/  /'
  n=$(say "$ec2" | grep -c .)
  add_cost 0.0416 "$n"
else
  say "  nenhuma instancia em execucao"
fi

head2 "Clusters EKS"
eks=$(aws eks list-clusters --region "$REGION" --query 'clusters[]' --output text 2>/dev/null)
if [ -n "$eks" ]; then
  for c in $eks; do say "  $c"; done
  n=$(printf '%s\n' $eks | grep -c .)
  add_cost 0.10 "$n"
else
  say "  nenhum cluster"
fi

head2 "Load balancers"
elb=$(aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].[LoadBalancerName,Type]' --output text 2>/dev/null)
if [ -n "$elb" ]; then
  say "$elb" | sed 's/^/  /'
  n=$(say "$elb" | grep -c .)
  add_cost 0.0225 "$n"
else
  say "  nenhum"
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
  say "  nenhum"
fi

head2 "IPs elasticos ociosos"
eip=$(aws ec2 describe-addresses --region "$REGION" \
  --query 'Addresses[?AssociationId==`null`].PublicIp' --output text 2>/dev/null)
if [ -n "$eip" ]; then
  for i in $eip; do say "  $i  (sem associacao, cobra)"; done
  n=$(printf '%s\n' $eip | grep -c .)
  add_cost 0.005 "$n"
else
  say "  nenhum"
fi

head2 "Volumes EBS soltos"
ebs=$(aws ec2 describe-volumes --region "$REGION" \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].[VolumeId,Size]' --output text 2>/dev/null)
if [ -n "$ebs" ]; then
  say "$ebs" | sed 's/^/  /'
else
  say "  nenhum"
fi

DAY=$(awk -v h="$TOTAL_HOUR" 'BEGIN{printf "%.2f", h*24}')
MONTH=$(awk -v h="$TOTAL_HOUR" 'BEGIN{printf "%.2f", h*730}')

head2 "Estimativa"
say "  por hora  ~ USD $TOTAL_HOUR"
say "  por dia   ~ USD $DAY"
say "  por mes   ~ USD $MONTH"
say ""
say "  Valores aproximados de tabela on-demand us-east-1, sem storage e sem trafego."
say "  Servem para ordem de grandeza, nao para conciliacao de fatura."

if [ "$(awk -v h="$TOTAL_HOUR" 'BEGIN{print (h>0)?1:0}')" = "1" ]; then
  say ""
  say "  Ha recursos cobrando. Para derrubar: ./scripts/teardown.sh"
fi
