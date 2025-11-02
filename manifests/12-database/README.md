# PostgreSQL Database

Shared PostgreSQL instance for homelab applications (LiteLLM, n8n, etc.)

## Architecture

- **Deployment Type**: StatefulSet (ordered scaling, stable network identity)
- **Version**: PostgreSQL 16 Alpine
- **Storage**: 20Gi persistent volume (storageClass: standard)
- **Service**: ClusterIP (internal cluster access only)
- **Namespace**: database

## Deployed Resources

```bash
kubectl get all,pvc -n database
```

Expected resources:
- 1 StatefulSet (postgres)
- 1 Pod (postgres-0)
- 1 Service (postgres - ClusterIP)
- 1 PVC (postgres-data-postgres-0 - 20Gi)
- 1 Secret (postgres-secret)

## Connection Information

### Internal Cluster Access

**Service DNS**: `postgres.database.svc.cluster.local`
**Port**: `5432`
**User**: `postgres`
**Password**: Stored in `postgres-secret`

### Connection String Format

```
postgresql://postgres:<password>@postgres.database.svc.cluster.local:5432/<database>
```

### Application-Specific Databases

Each application gets its own database:
- `litellm` - LiteLLM proxy cache and tracking
- `n8n` - n8n workflow automation

## Testing Connection

### From Mac (port-forward)

```bash
# Forward PostgreSQL port to localhost
kubectl port-forward -n database svc/postgres 5432:5432

# Connect with psql (requires PostgreSQL client installed)
psql -h localhost -U postgres -d postgres
# Password: homelab-postgres-2025-secure-k8s
```

### From inside cluster (debug pod)

```bash
# Run temporary PostgreSQL client pod
kubectl run -it --rm psql-client \
  --image=postgres:16-alpine \
  --restart=Never \
  --namespace=database \
  -- psql -h postgres.database.svc.cluster.local -U postgres

# Enter password when prompted
```

## Creating Application Databases

### Via port-forward

```bash
# Forward port
kubectl port-forward -n database svc/postgres 5432:5432

# Connect and create databases
psql -h localhost -U postgres -d postgres <<EOF
CREATE DATABASE litellm;
CREATE DATABASE n8n;
\l
EOF
```

### Via kubectl exec

```bash
# Execute SQL directly in pod
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "CREATE DATABASE litellm;"
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "CREATE DATABASE n8n;"

# List databases
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "\l"
```

## Integration Examples

### LiteLLM

```yaml
env:
- name: DATABASE_URL
  value: "postgresql://postgres:homelab-postgres-2025-secure-k8s@postgres.database.svc.cluster.local:5432/litellm"
```

### n8n

```yaml
env:
- name: DB_TYPE
  value: "postgresdb"
- name: DB_POSTGRESDB_HOST
  value: "postgres.database.svc.cluster.local"
- name: DB_POSTGRESDB_PORT
  value: "5432"
- name: DB_POSTGRESDB_DATABASE
  value: "n8n"
- name: DB_POSTGRESDB_USER
  value: "postgres"
- name: DB_POSTGRESDB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: POSTGRES_PASSWORD
```

## Maintenance

### Viewing Logs

```bash
kubectl logs -n database postgres-0 --tail=100 -f
```

### Checking Storage

```bash
kubectl get pvc -n database
kubectl describe pvc postgres-data-postgres-0 -n database
```

### Backup (manual)

```bash
# Dump all databases
kubectl exec -n database postgres-0 -- pg_dumpall -U postgres > backup-$(date +%Y%m%d-%H%M%S).sql

# Dump specific database
kubectl exec -n database postgres-0 -- pg_dump -U postgres litellm > litellm-backup.sql
```

### Restore from backup

```bash
# Restore all databases
kubectl exec -i -n database postgres-0 -- psql -U postgres < backup-20251101-123456.sql

# Restore specific database
kubectl exec -i -n database postgres-0 -- psql -U postgres litellm < litellm-backup.sql
```

## Troubleshooting

### Pod not starting

```bash
kubectl describe pod -n database postgres-0
kubectl logs -n database postgres-0
```

### PVC stuck in Pending

Check that storageClass is `standard` (NOT `local-path`):
```bash
kubectl get pvc -n database
kubectl describe pvc postgres-data-postgres-0 -n database
```

### Connection refused

Verify service and endpoints:
```bash
kubectl get svc -n database
kubectl get endpoints -n database
kubectl exec -n database postgres-0 -- netstat -tlnp | grep 5432
```

### Check PostgreSQL status

```bash
# Inside pod
kubectl exec -it -n database postgres-0 -- pg_isready -U postgres

# Check version
kubectl exec -it -n database postgres-0 -- psql -U postgres -c "SELECT version();"
```

## Security Notes

- **Password**: Currently in plaintext in secret.yaml (acceptable for homelab)
- **Network**: No external ingress (ClusterIP only)
- **Future**: Consider adding NetworkPolicy for namespace isolation
- **Backup**: Manual backups recommended before major changes

## Storage Details

- **PVC Name**: `postgres-data-postgres-0`
- **Size**: 20Gi
- **Access Mode**: ReadWriteOnce
- **StorageClass**: standard (kind's local-path provisioner)
- **Location**: `/var/lib/postgresql/data/pgdata` in container

## References

- PostgreSQL Official Image: https://hub.docker.com/_/postgres
- PostgreSQL Documentation: https://www.postgresql.org/docs/16/
- Research Note: `202511012146` (PostgreSQL planning)
