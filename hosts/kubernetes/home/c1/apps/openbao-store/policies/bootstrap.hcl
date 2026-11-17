# bootstrap: the agent box's one-time hand-over of the admin login, through the Kubernetes login's
# role bootstrap (service account openbao-bootstrap). It sets the admin AppRole's role ID and a
# secret ID the box chose, and deletes its own role; it can read nothing and set nothing else.
path "auth/approle/role/admin/role-id"          { capabilities = ["update"] }
path "auth/approle/role/admin/custom-secret-id" { capabilities = ["update"] }
path "auth/kubernetes/role/bootstrap"           { capabilities = ["delete"] }
