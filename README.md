# platform-chart

The central Helm chart every service deploys with (`chart/`). Its values are
not written by hand. `svcreg` generates them into the services repo
(`rendered/<env>/<svc>/values.yaml`), and Argo CD combines the two with a
multi-source Application.

`chart/capabilities.yaml` lists what the chart supports. The services repo
vendors it, and `svcreg` rejects manifests that use anything else.

| | |
|---|---|
| Profiles | `http-api` (Deployment or Rollout plus a Service on port 80, named after the service) and `worker` (no Service) |
| Kinds | `http-endpoint`, `nats-subject`, `sqs-queue` (deterministic names), `postgres` (dynamic; isolated in sandboxes by default) |

## What it renders

- **Config.** `configFile.refs` becomes one ExternalSecret. Each reference
  reads from its own `ClusterSecretStore`, and `configFile.template` builds
  `config.yaml` (ESO template engine v2). Without references, the config is a
  plain Secret. The pod mounts it at `/etc/service/config.yaml`, and the
  pod-template checksum rolls pods when it changes.
- **Workload.**
  - Long-lived environments get a Deployment, or an Argo Rollouts canary when
    `platform.rollouts.enabled`.
  - Sandboxes (`service.sandbox.name` set) always get a single-replica
    Deployment, with the sandbox node-pool toleration when
    `platform.sandbox.nodePool.enabled`.
- **Outputs.** Every entry in `outputs[]` with `provision: true` is created.
  - With `platform.provisioner: crossplane`, the chart emits
    `PostgresInstance` and `Queue` claims, and each claim's connection secret
    is the output.
  - With `local`, the chart provisions in-cluster stand-ins. Postgres runs as
    a StatefulSet whose connection secret ESO assembles from a generated
    Password. The queue is recorded in a ConfigMap stub.
  - Dynamic outputs get a PushSecret that publishes the connection secret to
    the outputs store (`/services/<env>/<svc>/<output>`, or
    `/sandboxes/<name>/<svc>/<output>`). Consumers read it back through their
    own ExternalSecret.

Every pod gets `SERVICE_NAME`, `ENVIRONMENT`, `SANDBOX_NAME`,
`SERVICE_VERSION`, `CONFIG_FILE` and `OTEL_PROPAGATORS=tracecontext,baggage`.

## Tests

```sh
tests/run.sh   # helm template + assertions per fixture, kubeconform with CRD schemas
```

The files in `tests/fixtures/` are values files from the services repo's
`rendered/` directory, plus a worker that has no references.
