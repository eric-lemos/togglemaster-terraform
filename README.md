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

O stack Helm instala Ingress NGINX, Metrics Server, Argo CD e a stack de
observabilidade descrita abaixo.
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

## Observabilidade no laboratório

As quatro releases são gerenciadas exclusivamente pelo Terraform no state Helm,
não pelo Argo CD. Essa escolha reaproveita o gerenciamento dos pacotes existentes.
O guia acadêmico menciona tanto código IaC/GitOps quanto charts no repositório
GitOps: documente essa decisão no relatório e confirme a interpretação com o
professor. Não crie Applications Argo CD para gerenciar as mesmas releases.

| Release | Chart fixado | Função |
| --- | --- | --- |
| `monitoring` | `kube-prometheus-stack` 92.17.0 | Prometheus, Alertmanager, Grafana e métricas Kubernetes |
| `loki` | `loki` 7.5.0 | Logs via OTLP, SingleBinary com uma réplica |
| `otel-agent` | `opentelemetry-collector` 0.178.2 | DaemonSet que coleta stdout/stderr dos contêineres |
| `otel-gateway` | `opentelemetry-collector` 0.178.2 | Recebe OTLP e encaminha logs e métricas |

As configurações ficam em [helm/values](helm/values), e o dashboard versionado
em [helm/dashboards/togglemaster.json](helm/dashboards/togglemaster.json).
O Collector Contrib usa a imagem fixada em 0.163.2. Os agentes excluem seus
próprios logs para evitar realimentação. A coleta começa no final dos arquivos:
gere novas requisições para visualizar logs depois da instalação.

Fluxo: logs dos contêineres -> agente -> gateway -> Loki. As futuras métricas
OTLP das aplicações serão expostas pelo gateway na porta 8889 e coletadas pelo
Prometheus. As métricas nativas do cluster são coletadas diretamente pelo
Prometheus. As portas OTLP internas do gateway são 4317 (gRPC) e 4318 (HTTP).
O pipeline de traces fica desativado até configurar o APM comercial.

O dashboard "ToggleMaster - Ecosystem", na pasta ToggleMaster, mostra CPU,
memória, reinícios, logs e requisições HTTP instrumentadas com OpenTelemetry.
O analytics-service não apresenta requisições HTTP de negócio: seu endpoint
de health é excluído da instrumentação.

O alerta `ToggleMasterAuthHighErrorRate`, definido em
[helm/alert-rules/auth-service.yaml](helm/alert-rules/auth-service.yaml), dispara
quando a proporção de respostas 5xx do auth-service ultrapassa 5% durante
2 minutos, com pelo menos 10 requisições estimadas nos últimos 5 minutos.
O Prometheus calcula o volume com `increase`, que extrapola valores entre
coletas; o limiar não é uma contagem exata de eventos. O alerta só é avaliado
quando há métricas de requisições. Ausência de telemetria não dispara esse
alerta. Após aplicar a stack Helm, confira a regra e seu estado em
`/prometheus/alerts`. O Alertmanager encaminha esse alerta ao Discord e ao
PagerDuty após a configuração abaixo. O self-healing do auth-service é gerenciado
no repositório GitOps e deve ser aplicado e validado separadamente. A rota do
webhook interno no Alertmanager fica desativada por padrão; só defina
`self_healing_webhook_enabled = true` em `helm/helm.auto.tfvars` depois de
preparar o receptor e os secrets conforme o README do GitOps. O repositório ECR
`togglemaster/webhook` é criado pelo Terraform para a imagem do
receptor.

### Notificações no Discord

No Discord, crie um webhook nas configurações do canal `chat-ops`, em
**Integrações > Webhooks**, e copie a URL. No repositório Terraform, configure
o GitHub Actions secret `DISCORD_WEBHOOK_URL` com a URL original, sem `/slack`.
Não coloque essa URL no Git nem a compartilhe: ela permite enviar mensagens ao
canal.

O workflow de apply exige esse secret e cria o Secret Kubernetes `discord-webhook`
no namespace `observability` antes de instalar o Helm. A URL não é passada ao
Terraform nem armazenada em seu state. O Alertmanager usa o endpoint compatível
com Slack do Discord e notifica apenas `ToggleMasterAuthHighErrorRate`, tanto
no disparo quanto na resolução. Os demais alertas continuam no receptor `null`.
Após recriar o cluster ou rotacionar o webhook, execute o apply novamente com o
secret atualizado. A URL permanece armazenada no Secret do Kubernetes; restrinja
o acesso a ele.

Para executar o apply local, crie os Secrets antes de aplicar o stack Helm:

```bash
(
  set -euo pipefail
  read -rs -p "Discord webhook URL: " DISCORD_WEBHOOK_URL; echo
  [[ "$DISCORD_WEBHOOK_URL" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]+/[A-Za-z0-9._-]+/?$ ]] || {
    echo "URL de webhook inválida; informe a URL original, sem /slack." >&2
    exit 1
  }
  kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
  webhook_file="$(mktemp)"
  trap 'rm -f "$webhook_file"' EXIT
  printf '%s/slack' "${DISCORD_WEBHOOK_URL%/}" > "$webhook_file"
  kubectl -n observability create secret generic discord-webhook \
    --from-file="url=$webhook_file" --dry-run=client -o yaml | kubectl apply -f -
)
```

Informe a URL original, sem `/slack` ou parâmetros. Em seguida, aplique o Helm
após configurar também o PagerDuty abaixo. A entrega real no canal deve ser verificada com um alerta
de teste; a existência da regra, por si só, não confirma a notificação.

### Incidentes no PagerDuty

Crie um serviço no PagerDuty em **Services > Service Directory > New Service**,
com uma política de escala. Na seção **Integrations**, selecione **Events API
v2** e copie a Integration Key. Se o serviço já existir, adicione a integração
na aba **Integrations**. Use a chave da integração Events API v2, não uma chave
da REST API nem a integração Prometheus (v1).

No repositório Terraform, crie o GitHub Actions secret
`PAGERDUTY_INTEGRATION_KEY` com essa chave. O apply exige a chave e cria o Secret
Kubernetes `pagerduty-integration` em `observability`. A chave não é passada ao
Terraform nem armazenada em seu state, mas permanece no Secret Kubernetes;
restrinja o acesso a ele. Não a envie no chat nem a versione no Git.

Para criar o Secret localmente depois de preparar o namespace no passo do
Discord:

```bash
(
  set -euo pipefail
  read -rs -p "PagerDuty Events API v2 integration key: " PAGERDUTY_INTEGRATION_KEY; echo
  [[ -n "$PAGERDUTY_INTEGRATION_KEY" && ! "$PAGERDUTY_INTEGRATION_KEY" =~ [[:space:]] ]] || {
    echo "Chave PagerDuty vazia ou contendo espaços." >&2
    exit 1
  }
  key_file="$(mktemp)"
  trap 'rm -f "$key_file"' EXIT
  printf '%s' "$PAGERDUTY_INTEGRATION_KEY" > "$key_file"
  kubectl -n observability create secret generic pagerduty-integration \
    --from-file="routing-key=$key_file" --dry-run=client -o yaml | kubectl apply -f -
)
```

Após criar os dois Secrets, aplique a stack Helm. O alerta
`ToggleMasterAuthHighErrorRate` é enviado ao Discord e ao PagerDuty; ao resolver,
o Alertmanager envia a resolução para ambos. Depois do apply, valide a abertura
e a resolução de um incidente de teste no PagerDuty. Ao recriar o cluster ou
rotacionar a chave, atualize o secret do GitHub e execute o apply novamente.

O dashboard "ToggleMaster - OTel Collector" mostra a saúde do pipeline: collectors
ativos, logs e métricas recebidos e enviados, falhas, fila do exporter, memória
e CPU. Os dados vêm das métricas internas dos collectors (porta 8888), coletadas
pelo job `otel-collector-internal` do Prometheus. Detalhes técnicos de cada
collector também podem ser vistos em `/prometheus/targets`.

**Armazenamento efêmero:** não são criados PVCs. Prometheus tem retenção de
3 dias limitada a 2 GB; Loki tem retenção de 72 horas. Recriar pods de
armazenamento perde o histórico, e alterar configurações/usuários no Grafana
pela interface não garante persistência. Configurações versionadas são
recriadas. Essa stack não é uma instalação de produção nem de alta disponibilidade.
Verifique CPU, memória e disco livres nos nós antes do apply; os limites são
iniciais para laboratório, não uma garantia de capacidade no EKS.

Loki e OTLP continuam apenas como Services internos, sem autenticação nem TLS;
não os exponha publicamente. Grafana, Prometheus e Alertmanager são publicados
por caminho no mesmo ingress nginx dos microsserviços, em HTTP:

| Caminho | Autenticação |
| --- | --- |
| `/grafana/` | Login do Grafana (`admin`, senha gerada pelo chart) |
| `/prometheus/` | Basic auth do nginx (`admin`, senha gerada pelo Terraform) |
| `/alertmanager/` | Basic auth do nginx (mesma credencial do Prometheus) |

A senha do basic auth é gerada por `random_password` e fica no state Helm e no
Secret `monitoring-ui-basic-auth` (hash bcrypt na chave `auth`). Nenhuma senha
fica no Git. Como não há TLS, use a exposição apenas no laboratório e não
publique senhas nem outputs de Secrets.

Instale usando o fluxo `terraform -chdir=helm plan/apply` descrito acima.
Para inspecionar o cluster, atualize antes o kubeconfig:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "$TF_VAR_eks_cluster_name"
kubectl get nodes
kubectl top nodes
kubectl -n observability get pods,svc,pvc
kubectl -n observability rollout status deployment/otel-gateway
kubectl -n observability rollout status daemonset/otel-agent
kubectl -n observability logs deployment/otel-gateway --tail=50
kubectl -n observability logs daemonset/otel-agent --tail=50
```

Acesse pelo navegador usando o endereço do ingress:

```bash
INGRESS=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$INGRESS/grafana/"
echo "http://$INGRESS/prometheus/"
echo "http://$INGRESS/alertmanager/"
kubectl -n observability get secret monitoring-grafana \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo
kubectl -n observability get secret monitoring-ui-basic-auth \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

O primeiro comando de senha é o login do Grafana; o segundo é o basic auth de
Prometheus e Alertmanager. Port-forward continua disponível; no WSL use
`kubectl -n observability port-forward svc/monitoring-grafana 3000:80 --address 0.0.0.0`
para abrir `http://localhost:3000` no navegador do Windows.

No Grafana, confira os datasources Prometheus
e Loki, o dashboard e os targets Prometheus. Consulte no Loki
`{k8s_namespace_name="togglemaster"}` depois de gerar novas requisições.
A porta 8889 só apresenta métricas de aplicação após receber dados OTLP;
não confunda um target acessível com a instrumentação concluída.

Validação local sem acesso ao cluster:

```bash
terraform -chdir=helm init -backend=false
terraform -chdir=helm validate
terraform -chdir=helm test
```

Os testes usam providers simulados e verificam releases, dashboard, endpoints,
armazenamento e preservação dos pacotes existentes. Não instalam nada no EKS.

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
DISCORD_WEBHOOK_URL
PAGERDUTY_INTEGRATION_KEY
```

`AWS_SESSION_TOKEN` é obrigatório apenas para credenciais temporárias. O secret `TF_VAR_RDS_INSTANCE_PASSWORDS` deve ser um objeto JSON em uma única linha:

```json
{"auth":"REPLACE_WITH_A_STRONG_PASSWORD","targeting":"REPLACE_WITH_A_STRONG_PASSWORD","flags":"REPLACE_WITH_A_STRONG_PASSWORD"}
```

As chaves precisam corresponder exatamente às instâncias definidas em `rds.instances`: `auth`, `targeting` e `flags`. O prefixo `TF_VAR_` faz o Terraform disponibilizar o conteúdo como a variável `rds_instance_passwords`. Nunca versione `secrets.auto.tfvars` nem coloque senhas reais no repositório.
