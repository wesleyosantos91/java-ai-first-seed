
# Convenções de packages

## Objetivo

Definir a organização do código Java utilizando
arquitetura Feature-Based pragmática.

É a **proposta** do kit (ADR-0001). Um projeto
existente com outra organização a registra no
ADR-0001 ("Revisão neste projeto") e só migra
por decisão explícita (skill `architecture-decision`).

Package base:
`com.example.kitapp`

## Princípios

- Organizar o código prioritariamente por funcionalidade.
- Manter componentes relacionados próximos.
- Criar somente packages necessários à funcionalidade.
- Evitar abstrações sem justificativa técnica.
- Manter regras de negócio independentes de infraestrutura.
- Não utilizar Ports, Use Cases ou Adapters por padrão.

## Estrutura de referência

```text
com/example/kitapp/
├── KitMainApplication.java
├── feature/
│   └── product/
│       ├── api/
│       │   ├── rest/v1/
│       │   │   ├── request/
│       │   │   ├── response/
│       │   │   └── mapper/
│       │   ├── grpc/
│       │   └── webhook/
│       ├── messaging/
│       │   ├── kafka/
│       │   │   ├── consumer/
│       │   │   ├── producer/
│       │   │   └── contract/
│       │   ├── sqs/
│       │   ├── sns/
│       │   └── rabbitmq/
│       ├── client/
│       │   ├── http/
│       │   ├── grpc/
│       │   └── webhook/
│       ├── service/
│       ├── domain/
│       │   ├── entity/
│       │   ├── valueobject/
│       │   ├── policy/
│       │   ├── event/
│       │   └── exception/
│       ├── persistence/
│       │   ├── repository/
│       │   └── mapper/
│       ├── scheduler/
│       └── batch/
│           ├── reader/
│           ├── processor/
│           └── writer/
└── shared/
    ├── exception/
    ├── validation/
    ├── observability/
    └── configuration/
```

## Responsabilidades

### api
Recebe requisições externas e adapta dados
de transporte para operações da aplicação.

Não deve conter SQL ou regras de negócio.

### messaging
Implementa integrações assíncronas como
Kafka, SQS, SNS e RabbitMQ.

Consumers recebem eventos.
Producers e publishers enviam mensagens.

### client
Encapsula chamadas a sistemas externos,
incluindo HTTP, gRPC e webhooks de saída.

### service
Coordena operações, transações, persistência
e integrações.

Não deve concentrar invariantes que pertençam
naturalmente às entidades do domínio.

### domain
Contém entidades, value objects, invariantes,
eventos e regras de negócio puras.

Não deve depender de Spring, JDBC, HTTP
ou bibliotecas de mensageria.

### persistence
Implementa o acesso a dados com a tecnologia
adotada pelo projeto e registrada em ADR
(Spring JDBC com JdbcClient/JdbcTemplate,
Spring Data JDBC, Spring Data JPA ou outra).

Trocar ou introduzir tecnologia de persistência
exige decisão (skill `architecture-decision`).

### scheduler
Implementa gatilhos e execuções agendadas.

### batch
Agrupa leitura, processamento e escrita
em operações de lote, quando necessário.

### shared
Contém componentes genuinamente transversais.

Não deve se tornar um depósito de classes
que não possuem responsabilidade clara.

## Evolução

Esta árvore representa possibilidades futuras.

Não criar packages vazios antecipadamente.

Novos componentes devem respeitar estas
convenções ou justificar uma exceção por ADR.
