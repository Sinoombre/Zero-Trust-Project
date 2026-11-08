# Zero Trust en AWS — Arquitecture

La arquitectura que se diseñó, basada en el enfoque Zero Trust; el tráfico entrante se filtra mediante AWS WAFv2, con reglas de detección de ataques SQLi, XSS y limitación de solicitudes, antes de llegar al Application Load Balancer (ALB). Las instancias EC2 se alojan en subredes privadas, sin direcciones IP públicas y con acceso administrativo controlado mediante AWS Systems Manager Session Manager.

Adicionalmente, se implementan controles de detección y auditoría con GuardDuty, Security Hub, AWS Config y CloudTrail. Finalmente, se configura un mecanismo de respuesta automatizada mediante EventBridge y Lambda, que permite aislar instancias ante hallazgos de amenazas de alta severidad y notificar al equipo mediante SNS.

```{text}
    ┌─────────────────────────── SECURITY PERIMETER ───────────────────────┐
    │                                                                      │
    │  Internet ──► WAFv2 (Rules: SQLi, XSS, RateLimit) ──► ALB            │
    │                                                        │             │
    │                         VPC (No Public IPs en EC2)     │             │
    │                         ┌──────────────────────────────▼──────────┐  │
    │                         │ Private Subnet                          │  │
    │                         │  EC2 (no SSH directo — Session Manager) │  │
    │                         │  IAM Roles (no access keys long-lived)  │  │
    │                         │  IMDSv2 enforced                        │  │
    │                         └─────────────────────────────────────────┘  │
    │                                                                      │
    │  ┌─────────────────────── DETECTIVE CONTROLS ─────────────────────┐  │
    │  │ GuardDuty  │  Security Hub  │  AWS Config  │  CloudTrail       │  │
    │  │ (threat)   │  (compliance)  │  (drift)     │  (audit log)      │  │
    │  └────────────────────────────────────────────────────────────────┘  │
    │                                                                      │
    │  ┌─────────────────────── RESPONSE ───────────────────────────────┐  │
    │  │ EventBridge Rule ──► Lambda Responder ──► SNS Alert            │  │
    │  │ (GuardDuty finding HIGH) → isolate instance → notify team      │  │
    │  └────────────────────────────────────────────────────────────────┘  │
    └──────────────────────────────────────────────────────────────────────┘
```

## Diagrama de flujo

```{mermaid}
flowchart TD
  subgraph PROVIDER["Provisionamiento"]
    ST["Stack Terraform"]
  end

  subgraph APP["Aplicación protegida"]
    N["Red y subredes [network.tf]"]
    SG["Grupos de seguridad [security_groups.tf]"]
    EC["EC2 privada [compute.tf]"]
    W["WAF [waf.tf]"] -- protege --> LB["Balanceador HTTPS [load_balancer.tf]"]
  end

  subgraph AUDIT["Registro y auditoría"]
    S3[("Buckets S3 [s3.tf]")]
    CT["CloudTrail [cloudtrail.tf]"]
    LR["Logs de red [logging.tf]"]
    AWS["AWS Config [config.tf]"]
  end

  subgraph SECURITY["Seguridad y detección"]
    IAM["Roles IAM [roles.tf]"]
    D["Detección AWS [detection.tf]"]
    EA["Endurecimiento de cuenta"]
    AC["Alertas de Costo [budgets.tf]"]
  end

  subgraph ANSWER["Respuesta"]
    LA["Lambda Responder [respondet.py]"]
  end

  %% Flujo
  OP(("Operador")) -- aplica configuración --> ST
  ST -- provisiona --> N
  ST -- provisiona --> SG
  ST -- provisiona --> EC
  ST -- provisiona --> W
  ST -- provisiona --> S3
  ST -- provisiona --> CT
  ST -- provisiona --> LR
  ST -- provisiona --> AWS
  ST -- provisiona --> IAM
  ST -- provisiona --> D
  ST -- provisiona --> EA
  ST -- provisiona --> AC
  ST -- provisiona --> LB
  D --. dispara respuesta .--> LA
  LA -- modifica instancia --> AEC["AWS EC2"]
  LA -- publica alerta --> ASNS["AWS SNS"]

  %% Estilos por modulos
  classDef ye fill:#FFF3D9,stroke:#FCCE15,color:#FCCE15
  classDef gr fill:#C4F6C8,stroke:#54C45E,color:#54C45E
  classDef rd fill:#FFD9D9,stroke:#FC6E6E,color:#FC6E6E
  classDef bl fill:#ECF5FF,stroke:#6EB1FF,color:#6EB1FF

  class N,SG,EC,W,LB ye
  class S3,CT,LR,AWS gr
  class IAM,D,EA,AC rd
  class ST,AEC,ASNS,OP,LA bl

```
