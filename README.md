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

O Terraform gerencia somente a infraestrutura AWS. Depois de **Terraform Ops →
Apply**, use **K8s Ops → Apply** no repositório GitOps para instalar os charts
e aplicar os manifests. Os valores, dashboards e alertas ficam no GitOps, e os
releases são gerenciados diretamente pelo Helm CLI, não por Terraform.

Para destruir pelo GitHub, execute **Terraform Ops → Destroy**. O workflow
consulta o EKS no state, desinstala os sete releases conhecidos e só então
destrói a infraestrutura. Falhas na consulta ou desinstalação interrompem o
destroy. O state Helm remoto antigo não é alterado nem apagado automaticamente.
Em um ambiente novo não é necessário migrar releases. Não aplique o state Helm
antigo; avalie sua retenção e dados sensíveis separadamente.

Para destroy local, com Helm e kubectl instalados e o backend inicializado:

```bash
bash scripts/uninstall_helm.sh
terraform destroy
```

A limpeza automática antiga de load balancers e ENIs não é executada: ela tinha
escopo amplo e poderia afetar recursos não relacionados. Se o destroy ficar
bloqueado, identifique e revise as dependências antes de removê-las manualmente.
Os scripts antigos `cleanup_loadbalancers.sh` e `cleanup_vpc_leftovers.sh` não
devem ser usados sem revisão: podem remover recursos além dos releases do projeto.
Não execute o destroy e o Apply do GitOps simultaneamente.

> **Atenção:** o Kubernetes aposentou o projeto Ingress NGINX em março de 2026;
> não haverá novas correções ou atualizações de segurança. Esta configuração
> mantém compatibilidade com os manifests atuais, mas para uso exposto à internet
> planeje migrar para um controller mantido ou para Gateway API. Consulte o
> [anúncio oficial de aposentadoria](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

## Observabilidade no laboratório

As quatro releases de observabilidade são gerenciadas pelo Helm CLI no workflow
GitOps, não pelo Terraform nem pelo Argo CD. Não crie Applications Argo CD
para gerenciar os mesmos releases.

| Release | Chart fixado | Função |
| --- | --- | --- |
| `monitoring` | `kube-prometheus-stack` 92.17.0 | Prometheus, Alertmanager, Grafana e métricas Kubernetes |
| `loki` | `loki` 7.5.0 | Logs via OTLP, SingleBinary com uma réplica |
| `otel-agent` | `opentelemetry-collector` 0.178.2 | DaemonSet que coleta stdout/stderr dos contêineres |
| `otel-gateway` | `opentelemetry-collector` 0.178.2 | Recebe OTLP e encaminha logs e métricas |

As configurações ficam em [helm/values](https://github.com/eric-lemos/togglemaster-gitops/tree/main/helm/values), e o dashboard versionado
em [helm/dashboards/togglemaster.json](https://github.com/eric-lemos/togglemaster-gitops/blob/main/helm/dashboards/togglemaster.json).
O Collector Contrib usa a imagem fixada em 0.163.2. Os agentes excluem seus
próprios logs para evitar realimentação. A coleta começa no final dos arquivos:
gere novas requisições para visualizar logs depois da instalação.

Fluxo: logs dos contêineres -> agente -> gateway -> Loki. As métricas
OTLP das aplicações são expostas pelo gateway na porta 8889 e coletadas pelo
Prometheus. As métricas nativas do cluster são coletadas diretamente pelo
Prometheus. As portas OTLP internas do gateway são 4317 (gRPC) e 4318 (HTTP).
O pipeline de traces fica desativado até configurar o APM comercial.

O dashboard "ToggleMaster - Ecosystem", na pasta ToggleMaster, mostra CPU,
memória, reinícios, logs e requisições HTTP instrumentadas com OpenTelemetry.
O analytics-service não apresenta requisições HTTP de negócio: seu endpoint
de health é excluído da instrumentação.

O alerta `ToggleMasterAuthHighErrorRate`, definido em
[helm/alert-rules/auth-service.yaml](https://github.com/eric-lemos/togglemaster-gitops/blob/main/helm/alert-rules/auth-service.yaml), dispara
quando a proporção de respostas 5xx do auth-service ultrapassa 5% durante
30 segundos, com pelo menos 10 requisições estimadas nos últimos 2 minutos.
Para o laboratório, as métricas das aplicações são coletadas e a regra é
avaliada a cada 15 segundos; a primeira notificação aguarda 5 segundos.
Enquanto o alerta permanecer ativo, as notificações ao Discord, PagerDuty e
self-healing são repetidas a cada 2 minutos.
O Prometheus calcula o volume com `increase`, que extrapola valores entre
coletas; o limiar não é uma contagem exata de eventos. O alerta só é avaliado
quando há métricas de requisições. Ausência de telemetria não dispara esse
alerta. Após aplicar a stack Helm, confira a regra e seu estado em
`/prometheus/alerts`. O Alertmanager encaminha esse alerta ao Discord e ao
PagerDuty após a configuração abaixo. O self-healing do auth-service é gerenciado
no repositório GitOps e deve ser aplicado e validado separadamente. A rota
fica desativada por padrão; após criar os Secrets e validar o receptor, defina
`SELF_HEALING_ENABLED=true` para autorizar reinícios e execute **K8s Ops →
Apply** para habilitar a rota. Ao desativar a variável, execute Apply
novamente para desativar a rota.

### Notificações no Discord e PagerDuty

Configure os secrets `DISCORD_WEBHOOK_URL` (URL original, sem `/slack`) e
`PAGERDUTY_INTEGRATION_KEY` (chave Events API v2) no repositório GitOps. O job
Helm cria os Secrets Kubernetes no namespace `observability`. Restrinja o acesso
a eles e não compartilhe os valores. Após configurar ou rotacionar as credenciais,
execute novamente **K8s Ops → Apply** e valide a entrega de um alerta.

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
| `/prometheus/` | Basic auth do nginx (`admin`, senha gerada pelo workflow GitOps) |
| `/alertmanager/` | Basic auth do nginx (mesma credencial do Prometheus) |

A senha do basic auth é gerada pelo workflow GitOps e fica no Secret
`monitoring-ui-basic-auth` (hash bcrypt na chave `auth`), não no state Terraform.
Nenhuma senha fica no Git. Como não há TLS, use a exposição apenas no laboratório e não
publique senhas nem outputs de Secrets.

Instale usando **K8s Ops → Apply** no GitOps.
Para inspecionar o cluster, atualize antes o kubeconfig:

```bash
aws eks update-kubeconfig --region "$AWS_REGION" --name "$(terraform output -raw eks_cluster_name)"
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

## GitHub Actions

O workflow `.github/workflows/terraform.yml` valida e planeja a infraestrutura
em pull requests e pushes relevantes para `main`. Planos exigem credenciais AWS,
não rodam em pull requests de forks e podem criar ou configurar o bucket de backend.

Na execução manual, selecione **Apply** para validar, planejar e aplicar a
infraestrutura, ou **Destroy** para desinstalar os releases conhecidos e depois
destruir a infraestrutura. Os charts são instalados pelo Apply do workflow GitOps.

As operações manuais de apply e destroy exigem `main`. Os planos gerados no
mesmo run são aplicados após as validações, sem uma etapa de aprovação manual.
Os artefatos de plano podem conter dados sensíveis e são retidos por um dia.
As execuções compartilham um grupo de concorrência para evitar operações
simultâneas; o GitHub mantém apenas uma execução pendente por grupo, podendo
substituir uma execução pendente mais antiga.

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
