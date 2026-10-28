# RDS

Cria um DB subnet group e instâncias Amazon RDS PostgreSQL.

Se `engine_version` não for informado numa instância, o módulo consulta a versão
padrão disponível mais recente do PostgreSQL 16 na região do provider. É possível
fixar uma versão explicitamente na configuração daquela instância.

## Entradas

| Variável             | Descrição                                            |
| -------------------- | ---------------------------------------------------- |
| `rds`                | Subnet group e mapa de instâncias.                   |
| `passwords`          | Mapa sensível de senhas, uma por chave de instância. |
| `subnet_ids`         | IDs de subnets por chave lógica.                     |
| `security_group_ids` | IDs de security groups por chave lógica.             |

No módulo raiz, `passwords` recebe `rds_instance_passwords`. Não versione senhas.

Para execução local, crie `secrets.auto.tfvars`:

```hcl
rds_instance_passwords = {
  auth       = "REPLACE_WITH_A_STRONG_PASSWORD"
  targeting  = "REPLACE_WITH_A_STRONG_PASSWORD"
  flags      = "REPLACE_WITH_A_STRONG_PASSWORD"
}
```

Na CI, configure o GitHub Secret `TF_VAR_RDS_INSTANCE_PASSWORDS` como JSON em uma linha, usando exatamente as chaves `auth`, `targeting` e `flags`, correspondentes a `rds.instances`. As senhas devem ter pelo menos oito caracteres e não podem conter `/`, `@`, aspas duplas ou espaços.

## Saídas

| Output                                              | Descrição                                  |
| --------------------------------------------------- | ------------------------------------------ |
| `db_subnet_group_name`                              | Nome do DB subnet group.                   |
| `instance_endpoints`                                | Endpoints das instâncias por chave lógica. |
| `instance_identifiers`, `instance_arns`, `db_names` | Metadados das instâncias.                  |