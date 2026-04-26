# Phase 1 — AWS Infrastructure

Set up the cloud resources needed for the MCP server.

## Checklist

1. **EC2 instance** — `t3.micro` (or `t3.small`), Amazon Linux 2023, Node.js 20,
    instance name roseburg-ai-grocery-lister-t3-micro
    SSH instructions: ```ssh -i roseburg-ai-grocery-lister-key-pair.pem ec2-user@ec2-54-146-160-115.compute-1.amazonaws.com```
**database configuration and user**
- database name: `grocery_lister`
- username: `sa_grocery_lister`
- password: `gr0c3ry-l1st3r`
2. **RDS PostgreSQL** — `db.t3.micro`, single-AZ, private subnet
3. **Security groups** — EC2 allows inbound 443; RDS allows inbound 5432 from EC2 only
4. **Elastic IP** + domain (optional) with HTTPS via Let's Encrypt / nginx reverse proxy
5. **S3** (optional) — for backups
