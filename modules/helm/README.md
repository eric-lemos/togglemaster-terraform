# Helm

Instala releases Helm no cluster EKS por meio do stack Terraform independente
em `helm/`, que chama este módulo.

## Entrada

| Variável | Descrição                                                                                  |
| -------- | ------------------------------------------------------------------------------------------ |
| `helm`   | Mapa `packages` com chart, repositório, versão, namespace, values e flags `enabled` e `upgrade_install`. |

Este módulo depende de um cluster EKS existente. O stack em `helm/` configura
o provider AWS/Helm para autenticar no cluster usando `aws eks get-token`.
`upgrade_install` permite ao Helm atualizar releases existentes.

## Saída

| Output             | Descrição                                |
| ------------------ | ---------------------------------------- |
| `release_statuses` | Status de cada release por chave lógica. |
