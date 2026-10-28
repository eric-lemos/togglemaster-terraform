# ToggleMaster Terraform

Infraestrutura AWS do ToggleMaster, provisionada com Terraform 1.16.0. O estado remoto usa um bucket S3, preparado pelo script `scripts/create_backend_bucket.sh`.

## Pré-requisitos

- Terraform 1.16.0
- AWS CLI autenticada em uma conta AWS com as permissões necessárias
- Bash, para executar o script de backend

## Execução local

Crie o arquivo `secrets.auto.tfvars`, que é ignorado pelo Git, com uma senha para cada instância RDS:

```hcl
rds_instance_passwords = {
  auth       = "REPLACE_WITH_A_STRONG_PASSWORD"
  evaluation = "REPLACE_WITH_A_STRONG_PASSWORD"
  flags      = "REPLACE_WITH_A_STRONG_PASSWORD"
}
```

As senhas devem ter pelo menos oito caracteres e não podem conter `/`, `@`, aspas duplas ou espaços.

Defina o bucket de state e a região. O nome do bucket S3 deve ser globalmente único:

```bash
export TF_BACKEND_BUCKET="my-unique-togglemaster-tfstate"
export AWS_REGION="us-east-1"
```

Prepare o backend e execute o Terraform:

```bash
bash scripts/create_backend_bucket.sh "$TF_BACKEND_BUCKET" "$AWS_REGION"

terraform init \
  -backend-config="bucket=$TF_BACKEND_BUCKET" \
  -backend-config="region=$AWS_REGION"

terraform plan
terraform apply
```

Para remover os recursos:

```bash
terraform destroy
```

## GitHub Actions

O workflow em `.github/workflows/ci-terraform.yml` executa os jobs `Validate`, `Plan`, `Security`, `Apply` e `Destroy`.

- `Validate`, `Plan` e `Security` rodam em pull requests e pushes para `main`.
- `Apply` exige execução manual no branch `main`, com `apply=true`. Ele aplica o plano gerado no mesmo workflow após validar seu checksum SHA-256.
- `Destroy` exige execução manual no branch `main`, com `DESTROY=true`. Nesse modo, os jobs `Validate`, `Plan`, `Security` e `Apply` são ignorados.

Configure em **Settings > Secrets and variables > Actions**:

### Variables

```text
AWS_REGION=us-east-1
TF_BACKEND_BUCKET=my-unique-togglemaster-tfstate
```

### Secrets

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN
TF_VAR_RDS_INSTANCE_PASSWORDS
```

`AWS_SESSION_TOKEN` é obrigatório apenas para credenciais temporárias. O secret `TF_VAR_RDS_INSTANCE_PASSWORDS` deve ser um objeto JSON em uma única linha:

```json
{"auth":"REPLACE_WITH_A_STRONG_PASSWORD","evaluation":"REPLACE_WITH_A_STRONG_PASSWORD","flags":"REPLACE_WITH_A_STRONG_PASSWORD"}
```

O prefixo `TF_VAR_` faz o Terraform disponibilizar o conteúdo como a variável `rds_instance_passwords`. Nunca versione `secrets.auto.tfvars` nem coloque senhas reais no repositório.
