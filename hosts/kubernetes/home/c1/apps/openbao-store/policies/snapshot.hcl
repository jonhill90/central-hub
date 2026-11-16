# snapshot: the hourly snapshot job in namespace openbao, through the Kubernetes login's role
# snapshot. It takes a snapshot and reads the one mark that says the store holds restored data, so
# it never snapshots a store that has only self-initialized (DESIGN section 6). No restore.
path "sys/storage/raft/snapshot" { capabilities = ["read"] }
path "kv/data/{{ .Values.markEnv }}/snapshot-mark" { capabilities = ["read"] }
