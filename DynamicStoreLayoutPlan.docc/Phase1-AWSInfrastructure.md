# Phase 1 — AWS Infrastructure

Set up the cloud resources needed for the MCP server.

## Checklist

1. **EC2 instance** — `t3.micro` (or `t3.small`), Amazon Linux 2023, Node.js 20
2. **RDS PostgreSQL** — `db.t3.micro`, single-AZ, private subnet
3. **Security groups** — EC2 allows inbound 443; RDS allows inbound 5432 from EC2 only
4. **Elastic IP** + domain (optional) with HTTPS via Let's Encrypt / nginx reverse proxy
5. **S3** (optional) — for backups
