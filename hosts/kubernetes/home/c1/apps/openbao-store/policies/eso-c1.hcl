# eso-c1: External Secrets Operator, through the Kubernetes login's role eso (D-0058 rule 5).
# Reads c1's secrets and nothing else: no list, no write, no other path.
path "kv/data/c1/*" { capabilities = ["read"] }
