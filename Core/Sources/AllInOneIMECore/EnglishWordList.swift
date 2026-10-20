import Foundation

extension EnglishWords {
    /// Product and technical words rime-ice's English dictionary (`melt_eng`: en_dicts/en.dict.yaml and en_ext.dict.yaml
    /// of rime-ice 2026.06.30) doesn't have, as their makers write them ("Core Data", "Argo CD", "SOC 2"), but a product
    /// named with a common English word in small letters ("nomad", "replicate", "storybook": typed in full it comes first,
    /// and the word isn't always the product): what people who type about AI, the cloud and software write in Chinese text
    /// too, and pinyin offered nothing for ("bedrock" became 比尔电容触控). Each was checked against that dictionary by its
    /// letters (`key`) and is offered only where it still lacks it (`EnglishWordsEngine`); none is a Chinese name in pinyin
    /// ("Xiaomi", "Taobao" are typed as 小米, 淘宝) or shorter than three letters. The Rime tests (`EnglishWordsRimeTests`)
    /// check that rime-ice lacks each, and that each is a word the user could add (`word`).
    public static let curated: [String] = [
        // AI: models, providers, frameworks, vector stores, terms.
        "Bedrock", "AgentCore", "SageMaker", "LangGraph", "LlamaIndex", "Hugging Face", "cuDNN", "Stable Diffusion", "vLLM",
        "QLoRA", "RLHF", "LLMs", "xAI", "Groq", "cohere", "replicate", "LiteLLM", "Vertex AI", "Gemma", "Mixtral",
        "Codestral", "Nemotron", "Imagen", "Veo", "ChatGLM", "Coze", "AutoGen", "CrewAI", "DSPy", "pinecone", "Weaviate",
        "Milvus", "chroma", "ChromaDB", "FAISS", "pgvector", "Qdrant", "Gradio", "Streamlit", "MLflow", "Kubeflow", "JAX",
        "TensorRT", "ONNX", "GGUF", "llama.cpp", "MLX", "Core ML", "MLOps", "embeddings", "tokenizers", "multimodal",
        "agentic", "fine-tune", "hallucination", "Claude Desktop",
        // Coding tools.
        "Kiro", "Cline", "Aider", "Zed", "Replit", "lovable",
        // AWS.
        "DynamoDB", "CloudWatch", "CloudFormation", "CloudTrail", "Fargate", "EKS", "ECS", "ECR", "redshift", "Kinesis",
        "SQS", "SNS", "IAM", "Cognito", "AppSync", "Lightsail", "Textract", "Rekognition", "Kendra", "GuardDuty",
        "EventBridge", "Step Functions", "ElastiCache", "QuickSight", "App Runner", "CodeCommit", "CodeBuild",
        "CodePipeline", "CodeDeploy",
        // Other clouds, hosting, operations.
        "GCP", "BigQuery", "Firestore", "Firebase", "spanner", "Dataflow", "Wrangler", "Fastly", "Akamai", "Heroku",
        "Fly.io", "Istio", "Podman", "caddy", "HAProxy", "nomad", "CircleCI", "Argo CD", "SonarQube", "Snyk", "Kibana",
        "Logstash", "Datadog", "Splunk", "PagerDuty", "New Relic", "OpenTelemetry", "Jaeger", "Zipkin", "Kustomize",
        "Skaffold", "Karpenter", "Crossplane", "Proxmox", "Unraid", "Synology", "SRE", "telemetry", "microservice",
        "microservices", "subnet", "VPC",
        // Data.
        "Cassandra", "Databricks", "airflow", "dbt", "Trino", "Parquet", "Sidekiq",
        // Programming: languages, packages, libraries.
        "pnpm", "Bun", "Deno", "SvelteKit", "rollup", "babel", "Jest", "storybook", "Redux", "Zustand", "rustc",
        "Pydantic", "NumPy", "pandas", "SciPy", "Matplotlib", "Jupyter", "Conda", "PyPI", "virtualenv", "Haskell",
        "OpenAPI", "monorepo", "hotfix", "rollback", "rollout", "idempotent", "crontab", "async", "full-stack", "codebase",
        // Security and sign-in.
        "SAML", "JWT", "CORS", "CSRF", "XSS", "OWASP", "SOC 2", "HIPAA", "SSO", "MFA", "OTP", "passkeys", "YubiKey",
        "Okta", "Auth0", "Keycloak",
        // Apple's platforms and frameworks.
        "visionOS", "AirPlay", "UIKit", "AppKit", "SwiftData", "Core Data", "CloudKit", "StoreKit", "ARKit", "RealityKit",
        "Android Studio",
        // Work: tools and the words of planning.
        "Jira", "Asana", "Miro", "Zapier", "Grammarly", "PRs", "WIP", "OKR", "OKRs", "KPIs", "ROI", "PRD", "POC", "SLA",
        "SLO", "IaaS", "backlog", "standup", "onboarding",
        // Companies and apps.
        "ByteDance", "DingTalk", "Bluesky", "DoorDash", "TSMC", "Duolingo",
    ]
}
