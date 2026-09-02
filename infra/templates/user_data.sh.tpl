#!/bin/bash
set -euo pipefail
dnf install -y jq git python3.13 python3.13-pip >/dev/null 2>&1 || dnf install -y jq git python3 python3-pip

REGION="${aws_region}"
GH_OWNER="${gh_owner}"
GH_REPO="${gh_repo}"
SSM_PAT_PARAM="${ssm_pat_param}"
RUNNER_VERSION="${runner_version}"

mkdir -p /opt/actions-runner
cd /opt/actions-runner
if [ ! -f config.sh ]; then
  curl -sL -o runner.tar.gz "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
  tar xzf runner.tar.gz
  rm -f runner.tar.gz
  ./bin/installdependencies.sh || true
fi

cat > /opt/actions-runner/register.sh <<'REG'
#!/bin/bash
set -euo pipefail
REGION="${aws_region}"
GH_OWNER="${gh_owner}"
GH_REPO="${gh_repo}"
SSM_PAT_PARAM="${ssm_pat_param}"
cd /opt/actions-runner
PAT=$(aws ssm get-parameter --name "$SSM_PAT_PARAM" --with-decryption --region "$REGION" --query Parameter.Value --output text)
REG_TOKEN=$(curl -sX POST -H "Authorization: token $${PAT}" \
  "https://api.github.com/repos/$${GH_OWNER}/$${GH_REPO}/actions/runners/registration-token" | jq -r .token)
./config.sh --url "https://github.com/$${GH_OWNER}/$${GH_REPO}" --token "$REG_TOKEN" \
  --labels "${runner_label}" --unattended --ephemeral --replace
REG
chmod +x /opt/actions-runner/register.sh

cat > /opt/actions-runner/deregister.sh <<'DEREG'
#!/bin/bash
set -euo pipefail
REGION="${aws_region}"
GH_OWNER="${gh_owner}"
GH_REPO="${gh_repo}"
SSM_PAT_PARAM="${ssm_pat_param}"
cd /opt/actions-runner
PAT=$(aws ssm get-parameter --name "$SSM_PAT_PARAM" --with-decryption --region "$REGION" --query Parameter.Value --output text)
REMOVE_TOKEN=$(curl -sX POST -H "Authorization: token $${PAT}" \
  "https://api.github.com/repos/$${GH_OWNER}/$${GH_REPO}/actions/runners/remove-token" | jq -r .token)
./config.sh remove --token "$REMOVE_TOKEN" || true
DEREG
chmod +x /opt/actions-runner/deregister.sh

cat > /etc/systemd/system/gha-runner.service <<'UNIT'
[Unit]
Description=GitHub Actions self-hosted runner (cvbot-embedder)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/actions-runner
ExecStartPre=/opt/actions-runner/register.sh
ExecStart=/opt/actions-runner/run.sh
ExecStop=/opt/actions-runner/deregister.sh
Restart=no
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now gha-runner.service
