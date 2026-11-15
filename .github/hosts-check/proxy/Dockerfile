# A stand-in Proxmox host for role proxmox_proxy's test (test_proxy.sh): Debian trixie with systemd as PID 1,
# sshd for Ansible, nginx serving 443 and 80 the way it does today, a stand-in pveproxy on 127.0.0.1:8006 and
# a stand-in pve-cluster unit. Test values only. The base is the newest trixie build at least two weeks old
# when it was pinned (trixie-20261027, published 2026-10-28; STD-0003 rule 1), by digest.
FROM debian@sha256:2dc419c6d7fe3dad0a2f9fd469c34cc90b0f9ba642d8fde837fe3d7d34a0e7f1
ENV DEBIAN_FRONTEND=noninteractive
# nginx at the version the host runs today (the old role's pin).
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv dbus openssh-server python3 curl openssl \
      ca-certificates iproute2 nginx=1.26.3-3+deb13u10 nginx-common=1.26.3-3+deb13u10 \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/nginx/sites-enabled/default \
 && mkdir -p /root/.ssh /etc/pve/local /opt/standin /run/sshd && chmod 0700 /root/.ssh \
 && systemctl enable ssh.service nginx.service
COPY standin_pveproxy.py /opt/standin/standin_pveproxy.py
COPY nginx-today.conf /etc/nginx/conf.d/proxmox.conf
COPY standin-pveproxy.service standin-pve-cluster.service /etc/systemd/system/
# Lab chain for the stand-in: a test root, and the web UI certificate for pve.example.test signed by it.
RUN cd /etc/pve/local \
 && openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=test-root -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign -keyout /opt/standin/root.key -out /opt/standin/root.pem 2>/dev/null \
 && openssl req -newkey rsa:2048 -nodes -subj /CN=pve.example.test -keyout pveproxy-ssl.key -out /opt/standin/web.csr 2>/dev/null \
 && printf 'subjectAltName=DNS:pve.example.test\nbasicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nauthorityKeyIdentifier=keyid\nsubjectKeyIdentifier=hash\n' > /opt/standin/san.ext \
 && openssl x509 -req -in /opt/standin/web.csr -CA /opt/standin/root.pem -CAkey /opt/standin/root.key -CAcreateserial \
      -days 30 -extfile /opt/standin/san.ext -out pveproxy-ssl.pem 2>/dev/null \
 && cp /opt/standin/root.pem /usr/local/share/ca-certificates/test-root.crt && update-ca-certificates >/dev/null \
 && systemctl enable standin-pveproxy.service standin-pve-cluster.service
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
