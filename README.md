# ossuary

infrastructure for [carp.rodeo](https://carp.rodeo) — Matrix homeserver on OVH Cloud with Rauthy (OIDC), Caddy (reverse proxy), and PostgreSQL.

see [docs/carp-rodeo-plan.md](docs/carp-rodeo-plan.md) for the full architecture plan.

## what's here

```
infra/           terraform — OVH instance + Cloudflare DNS
compose/         docker compose — caddy, rauthy, synapse, postgres
compose/static/  static landing page for carp.rodeo
docs/            architecture plans and notes
.github/         CI workflow (terraform plan/apply)
.sops.yaml       SOPS encryption rules (age key recipients)
```

## prerequisites

- [terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- [sops](https://github.com/getsops/sops) (`brew install sops`)
- [age](https://github.com/FiloSottile/age) (`brew install age`)
- OVH Cloud API credentials ([create token here](https://us.api.ovh.com/createToken/))
- Cloudflare API token (DNS edit permission for `carp.rodeo` zone)
- SSH key registered in OVH Cloud dashboard
- [Resend](https://resend.com) account + API key for transactional email
- OVH S3 buckets created in the Cloud dashboard:
  - `ossuary-tfstate` (terraform state)
  - `carp-rodeo-synapse-media` (Synapse media)
  - `carp-rodeo-rauthy-backups` (Rauthy Hiqlite backups)

## secrets management

all secrets are encrypted in-repo using [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age). no plaintext secrets in the repo, ever.

- `compose/.env` — docker compose secrets (encrypted, safe to commit)
- `infra/terraform.tfvars` — terraform variables (encrypted, safe to commit)
- `.sops.yaml` — config that tells SOPS which age key to use for which files

both your local machine and GitHub Actions decrypt with the same age private key. CI only needs 3 GitHub secrets (down from 6+).

## first-time setup

### 1. generate age keypair

```bash
make init-secrets
```

this creates `~/.config/sops/age/keys.txt` with your age keypair. then:

1. copy the **public key** into [.sops.yaml](.sops.yaml) (replace both `age1xxxxx` entries)
2. back up `~/.config/sops/age/keys.txt` somewhere safe (password manager, etc.)
3. save the **private key line** (starts with `AGE-SECRET-KEY-`) for the GitHub secret later

### 2. cloudflare cleanup

terraform manages DNS records but **will not delete existing ones it doesn't own**. before the first apply:

1. go to Cloudflare dashboard → DNS for `carp.rodeo`
2. delete the `@` A record pointing to GitHub Pages (or wherever it currently points)
3. delete any existing `synapse` or `auth` A/CNAME records
4. keep MX records and email routing config — terraform won't touch those

alternatively, import existing records into terraform state:

```bash
# find the record ID in cloudflare dashboard (or via API)
cd infra
terraform import cloudflare_record.root <zone_id>/<record_id>
```

### 3. generate encrypted secrets

```bash
make gen-tfvars    # creates infra/terraform.tfvars (encrypted)
make edit-tfvars   # opens in $EDITOR to fill in credentials
```

fill in the terraform variables:

| variable                 | where to get it                                                        |
| ------------------------ | ---------------------------------------------------------------------- |
| `ovh_application_key`    | [OVH token page](https://us.api.ovh.com/createToken/)                  |
| `ovh_application_secret` | same as above                                                          |
| `ovh_consumer_key`       | same as above                                                          |
| `cloudflare_api_token`   | Cloudflare dashboard → API Tokens → Create Token → Edit zone DNS       |
| `cloudflare_zone_id`     | Cloudflare dashboard → carp.rodeo → Overview → Zone ID (right sidebar) |
| `ssh_key_name`           | name of the SSH key in OVH Cloud → Project → SSH Keys                  |

```bash
make gen-env       # creates compose/.env with random secrets (encrypted)
make edit-env      # opens in $EDITOR to fill in remaining values
```

the `gen-env` command auto-generates random passwords for postgres, Rauthy encryption, Hiqlite secrets, and the bootstrap admin password. you still fill in:

- `SMTP_PASSWORD` — your Resend API key (starts with `re_`)
- `S3_ACCESS_KEY` / `S3_SECRET_KEY` — OVH S3 credentials

**save the bootstrap password** printed during `gen-env` — you need it for the first Rauthy login.

### 4. provision infrastructure

```bash
# set S3 backend creds for terraform state bucket
export AWS_ACCESS_KEY_ID=<your-ovh-s3-access-key>
export AWS_SECRET_ACCESS_KEY=<your-ovh-s3-secret-key>

make init     # terraform init (connects to S3 backend)
make plan     # preview what will be created
make apply    # create OVH instance + Cloudflare DNS records
make output   # show server IP, URLs, SSH command
```

### 5. DNS verification for Resend

after verifying `carp.rodeo` in the [Resend dashboard](https://resend.com/domains):

1. add the DKIM CNAME records Resend gives you to Cloudflare
2. SPF is already handled by terraform (`include:amazonses.com`)

### 6. deploy

```bash
make deploy   # syncs configs + decrypts .env to server + starts all services
```

### 7. bootstrap admin

1. open `https://auth.carp.rodeo/auth/v1/admin`
2. log in with `admin@carp.rodeo` + the bootstrap password from step 3
3. enroll a passkey for the admin account
4. clear the bootstrap password:
   ```bash
   make edit-env   # clear RAUTHY_BOOTSTRAP_PASSWORD value
   make deploy-env
   ssh debian@<server-ip> "cd /opt/carp-rodeo && docker compose restart rauthy"
   ```

### 8. configure Synapse OIDC client

1. in Rauthy Admin UI → Clients → New Client
2. client_id: `synapse`
3. redirect URI: `https://synapse.carp.rodeo/_synapse/client/oidc/callback`
4. scopes: `openid`, `profile`, `email`
5. flows: `authorization_code`
6. copy the client secret into `compose/synapse/homeserver.yaml` → `oidc_providers[0].client_secret`
7. `make deploy` to restart with the updated config

### 9. invite first user

1. Rauthy Admin UI → Users → Create User (enter their email)
2. Rauthy sends a magic link email (valid 7 days)
3. user clicks link → sets password → enrolls passkey
4. user opens a Matrix client → signs in via Rauthy → done

## ongoing operations

### update configs and redeploy

```bash
# edit compose files locally, then:
make plan         # if infra changed
make apply        # if infra changed
make deploy       # always — syncs compose + restarts
```

### edit secrets

```bash
make edit-env       # modify compose secrets (auto decrypt/re-encrypt)
make edit-tfvars    # modify terraform vars (auto decrypt/re-encrypt)
make decrypt-env    # print decrypted .env to stdout (for debugging)
```

### check things

```bash
make ssh              # shell into the server
make logs             # tail docker compose logs
make check-dns        # verify DNS records resolve correctly
make federation-test  # test Matrix federation via federationtester.matrix.org
```

### destroy everything

```bash
make destroy    # tears down OVH instance + DNS records (asks for confirmation)
```

## key rotation

### Rauthy encryption keys

Rauthy natively supports key rotation. add a new key without removing the old one:

```bash
make edit-env
# change: RAUTHY_ENC_KEYS=key01/oldbase64,key02/newbase64
# change: RAUTHY_ENC_KEY_ACTIVE=key02
make deploy-env
ssh debian@<server-ip> "cd /opt/carp-rodeo && docker compose restart rauthy"
```

Rauthy will use `key02` for new encryptions and `key01` to decrypt existing data. after a full cycle, remove `key01`.

### postgres password

```bash
make edit-env                # change POSTGRES_PASSWORD
make deploy-env
ssh debian@<server-ip> "cd /opt/carp-rodeo && docker compose exec postgres psql -U synapse -c \"ALTER USER synapse PASSWORD 'new-password';\""
ssh debian@<server-ip> "cd /opt/carp-rodeo && docker compose restart synapse"
```

### Resend API key

1. generate a new API key in [Resend dashboard](https://resend.com/api-keys)
2. `make edit-env` → update `SMTP_PASSWORD`
3. `make deploy-env` + restart rauthy
4. revoke the old key in Resend

### OVH S3 credentials

1. generate new credentials in OVH Cloud dashboard
2. `make edit-env` → update `S3_ACCESS_KEY` / `S3_SECRET_KEY`
3. `make deploy-env` + restart synapse
4. also update the local env vars for `make init` (S3 backend uses these)
5. revoke old credentials in OVH

### age key (SOPS)

to rotate the age key itself (re-encrypt all secrets with a new key):

```bash
# generate new keypair
age-keygen -o new-key.txt

# add both old and new public keys to .sops.yaml temporarily
# then re-encrypt both files
sops updatekeys compose/.env
sops updatekeys infra/terraform.tfvars

# update .sops.yaml to only have the new public key
# update SOPS_AGE_KEY GitHub secret with the new private key
# update ~/.config/sops/age/keys.txt with the new key
```

### OVH / Cloudflare API keys

1. generate new credentials in the respective dashboard
2. `make edit-tfvars` → update the values
3. update `S3_ACCESS_KEY` / `S3_SECRET_KEY` GitHub secrets if they changed
4. `make plan` + `make apply` to verify

## GitHub Actions secrets

the CI workflow needs only **3 secrets** (SOPS decrypts everything else from the repo):

| secret          | value                                                     |
| --------------- | --------------------------------------------------------- |
| `SOPS_AGE_KEY`  | age private key (`AGE-SECRET-KEY-...` line from keys.txt) |
| `S3_ACCESS_KEY` | OVH S3 access key (for terraform state backend)           |
| `S3_SECRET_KEY` | OVH S3 secret key (for terraform state backend)           |

set these at: GitHub → ossuary repo → Settings → Secrets and variables → Actions → New repository secret

the S3 credentials are needed because the terraform backend initializes before it can read the tfvars file. everything else (OVH API keys, Cloudflare token, etc.) is decrypted from the SOPS-encrypted `terraform.tfvars` in the repo.

## compose `.env` reference

all secrets for the docker compose stack. generated by `make gen-env`, stored encrypted at `compose/.env`.

| variable                    | auto-generated? | description                                                              |
| --------------------------- | :-------------: | ------------------------------------------------------------------------ |
| `POSTGRES_PASSWORD`         |       yes       | postgres password for synapse DB                                         |
| `RAUTHY_ENC_KEYS`           |       yes       | `key_id/base64_key` for Rauthy encryption (comma-separated for rotation) |
| `RAUTHY_ENC_KEY_ACTIVE`     |       yes       | active encryption key ID                                                 |
| `RAUTHY_HQL_SECRET_RAFT`    |       yes       | Hiqlite Raft consensus secret                                            |
| `RAUTHY_HQL_SECRET_API`     |       yes       | Hiqlite API secret                                                       |
| `RAUTHY_BOOTSTRAP_PASSWORD` |       yes       | temporary admin password (clear after setup)                             |
| `ADMIN_EMAIL`               |        —        | admin email, default `admin@carp.rodeo`                                  |
| `SMTP_URL`                  |        —        | `smtp.resend.com`                                                        |
| `SMTP_PORT`                 |        —        | `465`                                                                    |
| `SMTP_USERNAME`             |        —        | `resend`                                                                 |
| `SMTP_PASSWORD`             |     **no**      | Resend API key (`re_xxxxx`)                                              |
| `SMTP_FROM`                 |        —        | `carp.rodeo <auth@carp.rodeo>`                                           |
| `S3_ACCESS_KEY`             |     **no**      | OVH S3 access key                                                        |
| `S3_SECRET_KEY`             |     **no**      | OVH S3 secret key                                                        |
| `S3_ENDPOINT`               |        —        | `https://s3.us-east-va.perf.cloud.ovh.us`                                |
| `S3_REGION`                 |        —        | `us-east-1`                                                              |
| `S3_MEDIA_BUCKET`           |        —        | `carp-rodeo-synapse-media`                                               |
| `S3_BACKUP_BUCKET`          |        —        | `carp-rodeo-rauthy-backups`                                              |
