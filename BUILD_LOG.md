# Build Log: Switchyard + 3 Open Models + Grafana

A record of what I built, the decisions I made, and what I learned along the way.
Newest entries go at the bottom of each section. See `CLAUDE.md` for the overall plan.

---

## Current state

| Area | Status |
|---|---|
| Terraform: provider, lookups, key pair, SGs, 4 instances, outputs | ✅ done, applied, tested |
| Terraform → Ansible inventory (template + `local_file`) | ✅ done |
| Ansible: `swap` role (all hosts) | ✅ done, idempotent |
| Ansible: `ollama` role (model nodes) | ✅ done, verified on a node |
| Ansible: `ansible.cfg` with task timings | ✅ done |
| Ansible: `switchyard` role (gateway) | ✅ deployed by Ansible, service running, 4 routes |
| Ansible: `monitoring` role: Docker + Prometheus | ✅ Prometheus scraping Switchyard (target UP) |
| Grafana (provisioned Prometheus data source) | ✅ healthy, data source tested OK |
| node_exporter | ⬜ cut for the deadline (optional) |
| Load generator (`loadgen/loadgen.sh`) | ✅ running, all HTTP 200 |
| Grafana dashboard "Switchyard Demo" (5 panels) | ✅ built by hand; export JSON before destroy |
| Screenshots / recording, rehearsal | 🔄 in progress |

---

## 2026-10-02: Terraform foundations

**Built**
- `versions.tf`: AWS provider pinned `~> 6.0`, `profile = "accenture-demo"`, `region = var.region`
- `data.tf`: `aws_caller_identity` + `aws_region` to prove which account and region Terraform uses
- `variables.tf`: `region` (typed, with a default)
- Default VPC lookup: `data "aws_vpc"` with `default = true`

**Decisions**
- Credentials stay in `~/.aws/credentials` under a named profile; nothing in code.
- Region comes from a Terraform variable, not `~/.aws/config` (my config said `us-west-1`, so relying on it would have silently built in the wrong region).
- Look up the default VPC instead of creating one: I only need its ID, I don't own it.

**Lessons**
- `required_providers` = which plugin to download; `provider` block = how to configure it. Separate jobs.
- `alias` is not a profile. It creates a second copy of a provider.
- Without a `profile`, Terraform silently used my **default** profile (a different IAM user). The caller-identity output caught it.
- A variable does nothing until something reads it with `var.<name>`.
- A variable's `default` must be a literal value; it can't reference anything.
- `validate` passing ≠ correct. Always read the `plan`.
- IAM: the demo user didn't actually have EC2 permissions (`DescribeVpcs` → 403). Fixed with least privilege: `AmazonEC2FullAccess` only, not Administrator.

---

## 2026-10-03: AMI, key pair, security groups, instances, outputs, inventory

**Built**
- `data "aws_ami" "ubuntu_latest"`: owner Canonical `099720109477`, `most_recent = true`, name filter `ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*`
- `keys.tf`: dedicated ed25519 key `~/.ssh/accenture_demo`; `aws_key_pair` reads it with `file(pathexpand(var...))`
- `locals.tf`: port lists, `demo_models` map (node name → Ollama model), `my_ip_cidr`
- `security_groups_ingress.tf` / `security_groups_egress.tf`:
  - gateway SG: 22, 3000, 4000, 9090 from my IP only
  - model SG: 22 from my IP; 11434 (Ollama) + 9100 (node_exporter) **only from the gateway SG**
  - separate egress SG (all outbound), attached to every instance
- `instances.tf`: gateway `t3.small` (20 GB gp3); 3 model nodes `m7i-flex.large` (30 GB gp3) via `for_each = local.demo_models`, tagged `Name` + `Model`
- `outputs.tf`: gateway IP, Grafana/Switchyard/Prometheus URLs, model public + private IP maps (`for` expressions)
- `data "http" "my_ip"`: looks up my public IP on every run (`chomp()` + `/32`), so my IP is never stored in code
- `inventory.tftpl` + `local_file` → writes `ansible/inventory.ini` with current IPs, `ollama_model`, `private_ip`
- Providers pinned: aws `~> 6.0`, http `~> 3.6`, local `~> 2.9`
- `.gitignore`: `.terraform/`, `*.tfstate*`, `tfplan`, `*.tfvars`, `inventory.ini*`, keys, `.DS_Store`, `crash.log`
- Git repo initialised at the project root

**First apply:** 17 resources. `ansible all -m ping` → 4 × pong. Destroyed at end of session.

**Decisions**
- Look up the AMI (region-independent, always patched) instead of hard-coding an ID. In production I'd pin it.
- Filter AMIs by **owner ID**, because anyone can publish an image with an Ubuntu-looking name (AMI name squatting).
- Security-group-to-security-group rule for Ollama: survives IP changes, means exactly "only the gateway".
- Separate egress SG (option a): must be attached to all 4 instances.
- Map in `locals` for models: one source of truth for the Name tag, Model tag, and Ansible variable.
- Local state (gitignored), not S3: single user, no locking needed. In a team: S3 backend + locking + versioning + encryption.
- `StrictHostKeyChecking=accept-new` instead of disabling host key checking.

**Lessons**
- Leading wildcard `*ubuntu-noble…` matched Kubernetes (EKS) images. Anchor the start of patterns.
- `owners = ["self"]` means *my* account. Removing `owners` entirely makes the provider refuse (security).
- `resource` creates/owns; `data` only looks up.
- `setproduct` = every combination → would have created **9** model servers. Write the map out directly.
- `key_name` wants the key pair's **name** (`aws_key_pair.x.key_name`), not the path or the key contents.
- Instances attach **security groups**, not individual rules.
- `cpu_options` can't add CPUs; `instance_type` decides CPU and RAM.
- Quotes around a function call (`"file(...)"`) make it plain text. Test that a check *can* fail.
- `${ }` inserts a value into a string (like `{{ }}` in Jinja2).
- `for_each` needs strings or maps (numbers failed).
- A security group has no CIDR; reference it with `referenced_security_group_id`.
- Terraform templates only see variables passed into `templatefile()`; no `local.`/`var.` inside.
- `%{ for ~}`: tilde on the right only, or lines get glued together.
- `.gitignore` must be inside the repo. My first `git init` ran in `terraform/` by mistake.
- `.terraform.lock.hcl` **is** committed; it pins exact provider versions.
- Variable vs local vs output = function parameters vs internal values vs return values.
- `terraform plan -out=tfplan` + `terraform apply tfplan` applies exactly what was reviewed.
- `terraform console` lets me inspect any value before using it.

---

## 2026-10-04: Ansible roles: swap + ollama, then Switchyard

**Built**
- `ansible/site.yml`: "All Roles" play (`hosts: all`: `swap`), "Model Roles" play (`ollama`); gateway play to come
- `roles/swap`: `fallocate` (`creates: /swapfile`) → `0600` → `mkswap` / `swapon` only `when: ... is changed` → `/etc/fstab` via `lineinfile`. Default `swap_size: 4G`.
- `roles/ollama`:
  - `install.yml`: download amd64 `.tar.zst`, system user `ollama` (nologin), unpack to `/opt/ollama` (`creates:`), systemd unit template, handlers (reload + restart), enable + start
  - `model.yml`: wait for port 11434, `ollama list`, `ollama pull {{ ollama_model }}` only if missing
  - unit file: runs as `ollama`, `Environment="OLLAMA_HOST=0.0.0.0:11434"`
- `ansible/ansible.cfg`: `callbacks_enabled = ansible.posix.timer, ansible.posix.profile_tasks` (installed the `ansible.posix` collection)

**First playbook run:** `failed=0` on all 3 model nodes.
**Verified on a model node:** 4 GB swap active and in fstab; Ollama listening on `*:11434`; `llama3.2:3b` pulled; `ollama run` answers prompts.

**Decisions**
- One `ollama` role for all three nodes. **The inventory is the loop**: each host gets its own `ollama_model`.
- `swap` as its own reusable role (now also used on the gateway for the Switchyard Rust build).
- Model pull stays inside the `ollama` role (it needs the service running), split into task files.
- Ollama listens on `0.0.0.0`, safe because the security group only admits the gateway (defence in depth).

**Lessons**
- Terraform: I write the loop (`for_each`). Ansible: the inventory is the loop.
- Ollama listens on 127.0.0.1 by default; `OLLAMA_HOST` changes that.
- systemd: no quotes around `ExecStart`; `$PATH` isn't expanded; unit files owned by root; run services as a dedicated user.
- `is success` is almost always true (even for skipped tasks); use `is changed` to chain one-time steps.
- `command` tasks always report `changed`; use `creates:` to make them idempotent.
- Notify handlers from the task that changes config (the template), not from "start".
- Keep "enable + start" as a task: handlers react to change, tasks enforce state (and enable at boot).
- `--syntax-check` doesn't render templates; template typos only show up on a real run.
- `defaults/` (plural), or the role's variables are never loaded.
- `ec2-user` is Amazon Linux; Ubuntu AMIs use `ubuntu`.
- `buff/cache` in `free -h` is reclaimable, not "used".

**Switchyard (in progress)**
- Docs that matter: `INSTALLATION.md`, `docs/getting_started.md` (Server path), `docs/reference/toml_schema.md`, `crates/switchyard-server/README.md` (metrics).
- v0.3.0 server is release-validated on **Ubuntu 24.04 x86_64**, matching the gateway.
- Install: build tools + rustup → `cargo install --locked switchyard-server` (compiles from source; slow on t3.small, swap helps). The Python `nemo-switchyard` package isn't needed for the server.
- `routes.toml`: `[llm_clients.*]` (where: `format = "openai_chat"`, `base_url = http://<model-private-ip>:11434/v1`, no API key for Ollama) → `[targets.*]` (which model: `id`) → `[routes.*]` (name callers use + `type`: `passthrough` / `random` / `auto`).
- Run with `--host 0.0.0.0 --port 4000`; validate first with `--dry-run`.
- Endpoints: `/health`, `/v1/models`, `/v1/chat/completions`, `/metrics` (Prometheus).

**First hand-written `routes.toml`** (on the gateway, `/root/routes.toml`). The private IPs are from this session's apply and change after every destroy/apply, so this becomes a Jinja2 template next:

```toml
schema_version = 1

[llm_clients.demo-model-llama]
format = "openai_chat"
base_url = "http://172.31.26.128:11434/v1"

[llm_clients.demo-model-nemotron]
format = "openai_chat"
base_url = "http://172.31.17.177:11434/v1"

[targets.weak]
id = "llama3.2:3b"
llm_client = "demo-model-llama"

[targets.strong]
id = "nemotron-mini"
llm_client = "demo-model-nemotron"

[routes.smart]
id = "switchyard"
type = "auto"
capable_target = "strong"
efficient_target = "weak"
```

- `llm_client` = **where** (one per model node, its private IP); `target` = **which model** there; `route` = the name callers send as `"model"` + how to choose.
- My first draft still had the OpenRouter `base_url` and one client for two machines, and was missing `schema_version`.
- Test commands: `curl http://<model-private-ip>:11434/v1/models` from the gateway → `--dry-run` → run with `RUST_LOG=switchyard_server=debug,libsy=debug` to see routing decisions → from my Mac: `curl http://<gateway>:4000/v1/chat/completions -d '{"model":"switchyard",...}'`.
- ✅ **End-to-end working (by hand):** gateway reaches both Ollamas on private IPs → `--dry-run` = `server OK: switchyard` → server listening on `0.0.0.0:4000` → from my Mac, `/health` = `{"status":"ok"}` and a chat request to `"model":"switchyard"` was answered by **`llama3.2:3b`** (the `auto` route chose the efficient target), with token usage reported (`prompt_tokens: 32`, `completion_tokens: 43`).
- Path proven: **Mac → gateway SG (my IP only) → Switchyard :4000 → private IP → model SG (gateway SG only) → Ollama :11434 → model → back.**
- A server running in the foreground looks like a hang; it's waiting for requests.
- Next: save as `roles/switchyard/templates/routes.toml.j2`, looping over `groups['model_nodes']` with `hostvars[host].private_ip` / `.ollama_model`; capable/efficient choice goes in role defaults.
- Open design question: build Switchyard on every deploy (`cargo install`, 15+ min on t3.small) vs build once and ship the binary (`fetch` → `copy`), i.e. separate build from deploy.

---

## 2026-10-05: Switchyard role (deadline day)

**Built** (`roles/switchyard`, gateway play in `site.yml` tagged `gateway_roles`)
- Ships the **pre-built binary** (compiled once by hand, copied from the gateway to my Mac) with `copy`: no Rust toolchain or 15-minute compile on each rebuild. Binary is gitignored.
- Layout: `/opt/switchyard/bin/switchyard-server` (root, 0755), `/opt/switchyard/etc/routes.toml` (root:switchyard, 0640), `/etc/systemd/system/switchyard.service`.
- `routes.toml.j2`: loops over `groups['model_nodes']` with `hostvars[host].private_ip` / `.ollama_model` → one `llm_client` + one `target` per model node; one `auto` route `switchyard` (capable/efficient chosen in role defaults) + one `passthrough` route per model node.
- `template ... validate: "switchyard-server --config %s --dry-run"`: a broken config is never installed.
- systemd unit: `ExecStart=... --config ... --host 0.0.0.0 --port 4000`, runs as the `switchyard` user; handlers reload + restart; `wait_for` port 4000.

**Result:** service `active (running)` and `enabled`, routes `demo-model-llama, demo-model-nemotron, demo-model-qwen, switchyard`, using 2.4 MB of RAM.

**Decisions**
- Build once, deploy the artifact (the CI/CD pattern) instead of compiling on every deploy.
- `/opt/<app>` for the app, consistent with Ollama.
- Targets named after hosts, so the template has no `if` and no hard-coded model names; *which* model is capable/efficient is a variable (`-e capable_target=demo-model-qwen` on demo day).
- Passthrough route per model so the load generator can hit all three, giving a per-model breakdown in Grafana.

**Lessons**
- Every `notify:` needs a handler with exactly the same name (I forgot `handlers/main.yml` at first).
- systemd doesn't support `#` comments at the end of a line; they become arguments.
- `validate:` needs `%s` (Ansible checks the new temp file before replacing).
- `changed_when: false` on a template stops its handlers from ever firing.
- Jinja: no `{{ }}` inside `{% %}`; `~` is string join, not "matches"; every `if` needs `endif`; watch for curly quotes from copy/paste.
- TOML tables can't repeat; keep fixed headers out of loops.

---

### Monitoring role: Docker + Prometheus

**Built** (`roles/monitoring`, task files `docker.yml`, `prometheus_setup.yml`, `grafana_setup.yml`, each tagged)
- Docker from Ubuntu's packages (`docker.io`, `docker-compose-v2`); `hello-world` proved the gateway can pull from Docker Hub (egress SG works).
- `docker_compose.j2` → `/opt/monitoring/docker-compose.yml`: `prom/prometheus`, port 9090, config **bind-mounted read-only** to `/etc/prometheus/prometheus.yml`, named volume for data.
- `prometheus_setup.j2` → `/opt/monitoring/prometheus/prometheus.yml`: one job scraping Switchyard at the gateway's **private IP** (`ansible_default_ipv4.address`) `:4000`.
- `docker compose up -d` with `changed_when` on stderr; handler `docker compose restart prometheus` on config change.

**Result:** Prometheus → Status → Targets: `switchyard` **UP** (`http://<gateway-private-ip>:4000/metrics`, 1 ms scrape).

**Lessons**
- VS Code applies a Prometheus schema to any file named `prometheus.yml`, so my Ansible task file showed red. Renamed it `prometheus_setup.yml`.
- `template` with `dest:` = a directory names the file after the source (`docker_compose.j2`). Always give the full file path.
- Compose: no `version:` key any more; ports as quoted list items; volumes as `"src:dest"` strings; named volumes get names, not paths.
- Inside a container, `localhost` is the container, so scrape the host by its private IP.
- Tags on `import_tasks` apply to every task in the file; tags inherit play → role → imports. In `{ }` YAML, commas separate keys (use `[a, b]` for several tags).
- Past my 12:30 checkpoint, so I switched to "Claude drafts, I review and run" for the rest of monitoring.

### Monitoring role: Grafana

**Built**
- Second service in the same compose file: `grafana/grafana`, port 3000, `grafana_data` volume, `depends_on: prometheus`.
- Data source **provisioned as code** (`grafana_datasource.j2` → `/opt/monitoring/grafana/provisioning/datasources/prometheus.yml`, bind-mounted read-only): `url: http://prometheus:9090`, `access: proxy`, `isDefault: true`.
- Compose steps moved to their own task file (`docker_compose.yml`), imported **last** and tagged `[prometheus, grafana, compose]`, so Grafana's files exist before the containers start.

**Result:** Grafana 13.2.3 healthy; the Prometheus data source exists without any clicking, and its health check says "Successfully queried the Prometheus API."

**Lessons**
- Compose puts all services on one private network with built-in DNS, so `prometheus` resolves to that container's IP. Names survive container recreation; IPs don't.
- `access: proxy` = the Grafana server makes the query (inside Docker), not my browser.
- Grafana reads provisioning at startup, so the order of tasks matters.
- Docker publishes ports on `0.0.0.0` and bypasses the host firewall; the AWS security group is the real gatekeeper.

---

### Switchyard metrics actually exposed (v0.3.0, read from `/metrics`)

`switchyard_total_requests` has **no model label**, but these do:

| Metric | Labels | Use |
|---|---|---|
| `switchyard_requests_total` | `model` | requests per model |
| `switchyard_prompt_tokens_total`, `switchyard_completion_tokens_total` | `model` | tokens in/out per model |
| `switchyard_model_call_latency_ms_{bucket,sum,count}` | `model` | latency per model (histogram) |
| `switchyard_decisions_total` | `algorithm`, `selected_model` | which model each route type chose (shows `auto` decisions) |
| `switchyard_client_responses_total` | `outcome` (ok, other_error, retryable_error, client_disconnected) | errors |
| `switchyard_upstream_attempts_total` | `code`, `outcome` | upstream HTTP codes (200/404/429/500/504) |
| `switchyard_routing_overhead_ms_*` | `algorithm` | time Switchyard spends deciding |

Dashboard queries (PromQL):
- Requests/s per model: `sum by (model) (rate(switchyard_requests_total[1m]))`
- Output tokens/s per model: `sum by (model) (rate(switchyard_completion_tokens_total[1m]))`
- Avg latency per model: `sum by (model) (rate(switchyard_model_call_latency_ms_sum[5m])) / sum by (model) (rate(switchyard_model_call_latency_ms_count[5m]))`
- p95 latency: `histogram_quantile(0.95, sum by (le, model) (rate(switchyard_model_call_latency_ms_bucket[5m])))`
- Errors/s: `sum by (outcome) (rate(switchyard_client_responses_total{outcome!="ok"}[5m]))`
- Routing decisions: `sum by (algorithm, selected_model) (rate(switchyard_decisions_total[5m]))`

### Load generator + dashboard

**Built**
- `loadgen/loadgen.sh` (drafted by Claude, reviewed and paraphrased by me): stands in for an AI agent. 70% easy / 30% hard prompts; routes weighted toward `switchyard` (auto) 3/8, llama 2/8, nemotron 2/8, qwen 1/8; max 3 requests in flight; `max_tokens` 256; prints route → model that answered, HTTP code, seconds, tokens in/out. Settings overridable with env vars (`CONCURRENCY=1 ./loadgen.sh`).
- Grafana dashboard **"Switchyard Demo"**, built by hand: Requests/s per model, Output tokens/s per model, Avg latency per model, Errors/s, Routing decisions (algorithm + selected model).

**Observed**
- `switchyard` (auto) + easy prompt → `llama3.2:3b` in about 2 s: the router picked the efficient model.
- Hard prompt on llama: 70 s for 256 output tokens, so about 3–4 tokens/s on 2 vCPUs (CPU-only).
- qwen3 (reasoning model) used about 190 "thinking" tokens to answer "hello": why routing easy prompts away from it saves time and cost.
- All requests HTTP 200; errors panel flat, apart from `client_disconnected` when I stopped the load generator with Ctrl+C (in-flight requests cut off). The monitoring caught a real event.
- **`auto` chose llama for every prompt, including hard ones.** The stage router scores tool-calling signals in agent conversations; plain one-off chat has none, so it stays on the efficient target. For plain chat, an `llm_classifier` route (a judge model classifies difficulty first) would fit better; that's the next experiment.
- **Head-of-line blocking:** easy prompts on llama sometimes took 67–72 s for 3–27 output tokens, because they waited behind a 256-token hard request on the same CPU node. Latency = queueing + generation. Fixes: more replicas (`random` route), GPUs, separating hard traffic.
- **qwen on an easy prompt:** 17 tokens in, **256 out (cap reached, mostly "thinking")**, 164 s. Avg latency panel: qwen about 85–150 s vs llama/nemotron about 20–50 s under load.
- Stat panel "output tokens in selected range" (`increase(...[$__range])`) matched the sum of the load generator's `out` values for the same window.

**Lessons**
- `${VAR:-default}` in bash = `| default()` in Jinja2; `$( )` runs a command and uses its output; `&` runs in the background; `jobs -rp | wc -l` counts running background jobs.
- The `"model"` field picks a Switchyard **route**, not necessarily a model; `switchyard` is the name of the auto route.
- `rate()` turns ever-increasing counters into per-second values; set the time range to "Last 15 minutes" + 5 s refresh for a live demo.
- The dashboard lives in Grafana's Docker volume, so `terraform destroy` deletes it unless it's exported as JSON (and ideally provisioned like the data source).

---

## Command cheat sheet

**Terraform** (run in `terraform/`)

| Command | What it does |
|---|---|
| `terraform init` | download providers (rerun after adding one, e.g. http, local) |
| `terraform init -upgrade` | move providers to newer versions within the constraints |
| `terraform fmt` / `terraform fmt -check -diff` | fix / check formatting |
| `terraform validate` | syntax and reference check (not proof of correctness) |
| `terraform plan` | preview changes; read it and count resources |
| `terraform plan -out=tfplan` | save the exact plan |
| `terraform apply tfplan` | apply exactly the saved plan |
| `terraform output` / `terraform output -json <name>` | show outputs (IPs, URLs) |
| `terraform -chdir=../terraform <cmd>` | run against another folder |
| `terraform console` | inspect values interactively (`data.http.my_ip.response_body`, ...) |
| `terraform providers` | which providers the code requires |
| `terraform version` | CLI + installed provider versions |
| `terraform show tfplan` | read a saved plan |
| `terraform destroy` | remove everything Terraform created |
| `terraform state list` | what Terraform tracks (empty after destroy) |

**Ansible** (run in `ansible/`)

| Command | What it does |
|---|---|
| `ansible-galaxy init roles/<name>` | create a role skeleton |
| `ansible-galaxy collection install ansible.posix` | install the timer/profile_tasks callbacks |
| `ansible-inventory -i inventory.ini --graph --vars` | check the inventory parses and the variables |
| `ansible all -i inventory.ini -m ping` | test SSH + Python on every host |
| `ansible-playbook -i inventory.ini site.yml --syntax-check` | YAML/structure check (no templates) |
| `ansible-playbook -i inventory.ini site.yml --list-tasks` | show tasks in order |
| `ansible-playbook -i inventory.ini site.yml` | run it (run twice: second should be `changed=0`) |
| `ansible-playbook ... --tags model_roles` | run only tagged plays |
| `ansible-config dump --only-changed` | see which ansible.cfg settings are active |

**AWS / SSH / checks**

| Command | What it does |
|---|---|
| `aws sts get-caller-identity --profile accenture-demo` | which IAM identity is in use |
| `aws iam list-attached-user-policies --user-name ... --profile default` | check IAM permissions |
| `aws ec2 describe-images --owners 099720109477 ...` | find Ubuntu AMI names |
| `ssh -i ~/.ssh/accenture_demo ubuntu@<ip>` | log in to an instance |
| `ssh-keygen -R <ip>` | remove a stale known_hosts entry |
| `free -h`, `swapon`, `ss -tlnp \| grep 11434` | check swap and listening ports |
| `/opt/ollama/bin/ollama list` / `run <model> --verbose` | check and test a model |
| `curl http://<gateway>:4000/health` / `/v1/stats` / `/metrics` | check Switchyard |

---

## Interview talking points

- Credentials in a named profile, never in code; proved the identity with `aws_caller_identity`.
- Least privilege: the Terraform user has EC2 permissions only. Didn't widen it for SSM.
- AMI by data source, filtered by Canonical's owner ID (name squatting); would pin in production.
- Ollama reachable only from the gateway SG, on private IPs; `0.0.0.0` bind is safe because of the SG.
- One source of truth: `demo_models` map → instance tags → generated inventory → Ansible host vars.
- Local state for a one-person demo; S3 + locking + versioning + encryption for a team (seen at 8x8).
- `plan -out` + `apply tfplan` = apply exactly what was reviewed (the CI/CD pattern).
- Idempotency proven by a second playbook run with `changed=0`.
- `accept-new` host key checking instead of disabling it.
- Terraform iterates over data; Ansible iterates over hosts.
- In production: GPU instances for models; Switchyard and the dashboards work the same way.

---

## Cost habits

- `terraform destroy` at the end of every session; `terraform state list` should print nothing.
- Stopping isn't free (EBS is still charged); destroy for anything longer than a short break.
- Rough running cost: about $0.30/hour for all 4 instances, plus public IPv4 and EBS.
- Set a zero-spend budget plus a monthly budget alert in Billing.
