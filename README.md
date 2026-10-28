# ToggleMaster Terraform

Infraestrutura AWS do ToggleMaster, provisionada com Terraform 1.16.0. O estado remoto usa um bucket S3, preparado pelo script `scripts/create_backend_bucket.sh`.

## Pré-requisitos

- Terraform 1.16.0
- AWS CLI autenticada em uma conta AWS com as permissões necessárias
- Bash, para executar o script de backend
- Uma IAM role chamada `LabRole` (ou os nomes configurados em `eks.iam`) na mesma
  conta das credenciais AWS, com trust relationship e permissões exigidas pelo EKS.

## Execução local

Crie o arquivo `secrets.auto.tfvars`, que é ignorado pelo Git, com uma senha para cada instância RDS:

```hcl
rds_instance_passwords = {
  auth       = "REPLACE_WITH_A_STRONG_PASSWORD"
  targeting  = "REPLACE_WITH_A_STRONG_PASSWORD"
  flags      = "REPLACE_WITH_A_STRONG_PASSWORD"
}
```

As senhas devem ter pelo menos oito caracteres e não podem conter `/`, `@`, aspas duplas ou espaços.

Defina a região AWS. O nome do bucket de state é gerado de forma determinística
a partir do ID da conta AWS e da região (`togglemaster-tfstate-<account-id>-<region>`).
Assim, não é necessário escolher um nome global manualmente; o mesmo nome é usado
em execuções futuras na mesma conta e região:

```bash
export AWS_REGION="us-east-1"
export TF_BACKEND_BUCKET="$(bash scripts/backend_bucket_name.sh "$AWS_REGION")"
```

Se já houver um state em outro bucket acessível, migre-o antes da próxima execução
com `terraform init -migrate-state` e os mesmos parâmetros `-backend-config`.
O bucket fixo anterior `bkt-togglemaster-tfstate` não será mais usado.

Prepare o backend e execute o Terraform:

```bash
bash scripts/create_backend_bucket.sh "$TF_BACKEND_BUCKET" "$AWS_REGION"

terraform init \
  -backend-config="bucket=$TF_BACKEND_BUCKET" \
  -backend-config="region=$AWS_REGION"

terraform plan
terraform apply
```

O Helm é gerenciado por um stack Terraform separado, com state próprio
(`helm/terraform.tfstate`), e instalado depois que o EKS estiver disponível.
O workflow aplica a infraestrutura e os charts em sequência, com um único
acionamento manual da pipeline. Para execução local, aplique os dois stacks:

```bash
terraform apply

export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_eks_cluster_name="$(terraform output -raw eks_cluster_name)"
terraform -chdir=helm init \
  -backend-config="bucket=$TF_BACKEND_BUCKET" \
  -backend-config="region=$AWS_REGION"
terraform -chdir=helm plan
terraform -chdir=helm apply
```

O stack Helm instala Ingress NGINX, Metrics Server e Argo CD.
O controller Ingress usa a classe `nginx` e um Service `LoadBalancer`; as subnets
públicas recebem as tags AWS necessárias para descoberta pelo Kubernetes. O
manifesto do GitOps encaminha os cinco serviços por prefixo de caminho. Não há
hostname nem TLS configurados neste momento, então o acesso é feito pelo endereço
do Load Balancer em HTTP. O provider Helm acessa o endpoint do EKS com AWS CLI,
sem exigir kubeconfig local.

O workflow GitHub Actions usa um único acionamento manual: aplica o plano de
infraestrutura, espera o EKS ficar ativo e então inicializa, planeja e aplica o
stack Helm separado. No destroy, remove os releases antes de limpar os Load
Balancers e destruir o EKS.

Para remover os recursos manualmente:

```bash
export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_eks_cluster_name="$(terraform output -raw eks_cluster_name)"
terraform -chdir=helm init \
  -backend-config="bucket=$TF_BACKEND_BUCKET" \
  -backend-config="region=$AWS_REGION"
terraform -chdir=helm destroy
terraform destroy
```

Se os releases já tiverem sido aplicados pelo stack raiz anterior, transfira
o gerenciamento para o state separado antes de executar `terraform apply` na
infraestrutura. Com o backend principal inicializado, importe cada release no
stack Helm:

```bash
export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_eks_cluster_name="$(terraform output -raw eks_cluster_name)"
terraform -chdir=helm init \
  -backend-config="bucket=$TF_BACKEND_BUCKET" \
  -backend-config="region=$AWS_REGION"
terraform -chdir=helm import \
  'helm_release.this["ingress-nginx"]' \
  ingress-nginx/ingress-nginx
terraform -chdir=helm import \
  'helm_release.this["metrics-server"]' \
  kube-system/metrics-server
terraform -chdir=helm import \
  'helm_release.this["argocd"]' \
  argocd/argocd
```

Confirme que os releases aparecem com `terraform -chdir=helm state list`.
Depois remova as referências correspondentes do state raiz sem desinstalá-los:

```bash
terraform state rm \
  'module.helm.helm_release.this["ingress-nginx"]' \
  'module.helm.helm_release.this["metrics-server"]' \
  'module.helm.helm_release.this["argocd"]'
```

Faça a remoção apenas depois de confirmar os imports no state Helm.

> **Atenção:** o Kubernetes aposentou o projeto Ingress NGINX em março de 2026;
> não haverá novas correções ou atualizações de segurança. Esta configuração
> mantém compatibilidade com os manifests atuais, mas para uso exposto à internet
> planeje migrar para um controller mantido ou para Gateway API. Consulte o
> [anúncio oficial de aposentadoria](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

## GitHub Actions

O workflow em `.github/workflows/ci-terraform.yml` executa os jobs `Validate`, `Plan`, `Security`, `Apply` e `Destroy`.

- `Validate`, `Plan` e `Security` rodam em pull requests e pushes para `main`.
- `Apply` exige execução manual no branch `main`, com `apply=true`. Aplica o plano de infraestrutura e, em seguida, planeja/aplica o stack Helm separado no mesmo workflow.
- `Destroy` exige execução manual no branch `main`, com `destroy=true`. Ele remove primeiro os releases Helm e depois a infraestrutura; os jobs `Validate`, `Plan`, `Security` e `Apply` são ignorados.

Configure em **Settings > Secrets and variables > Actions**:

### Variables

```text
AWS_REGION=us-east-1
```

O workflow gera `TF_BACKEND_BUCKET` dinamicamente usando a conta autenticada e
`AWS_REGION`; não é preciso cadastrar essa variável no GitHub. Se uma variável
`TF_BACKEND_BUCKET` antiga existir nas Actions, ela não será mais usada.
Um bucket já pertencente à sua conta será reutilizado e terá versionamento,
criptografia e bloqueio de acesso público verificados/configurados pelo script.

As roles do EKS são resolvidas pelos nomes `cluster_role_name` e `node_role_name`
em `variables.auto.tfvars`, dentro da conta das credenciais utilizadas pelo
workflow. Isso evita passar uma ARN de role de outra conta. A role precisa
permitir o serviço EKS assumi-la, ter as políticas necessárias e ser passável
pela identidade AWS do workflow.

Por padrão, o módulo RDS busca na região selecionada a versão padrão disponível
mais recente do PostgreSQL 16. Também é possível informar `engine_version`
explicitamente em cada instância RDS.

### Secrets

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
TF_VAR_RDS_INSTANCE_PASSWORDS
```

`AWS_SESSION_TOKEN` é obrigatório apenas para credenciais temporárias. O secret `TF_VAR_RDS_INSTANCE_PASSWORDS` deve ser um objeto JSON em uma única linha:

```json
{"auth":"REPLACE_WITH_A_STRONG_PASSWORD","targeting":"REPLACE_WITH_A_STRONG_PASSWORD","flags":"REPLACE_WITH_A_STRONG_PASSWORD"}
```

As chaves precisam corresponder exatamente às instâncias definidas em `rds.instances`: `auth`, `targeting` e `flags`. O prefixo `TF_VAR_` faz o Terraform disponibilizar o conteúdo como a variável `rds_instance_passwords`. Nunca versione `secrets.auto.tfvars` nem coloque senhas reais no repositório.
