# Runbook: OPS-HARDEN production cutover (one-time, owner)

Run this once, by hand, on the production VM, around the first deploy of the
`agent/OPS-HARDEN-compose` changes. Read it fully before merging the branch to `main`.

What the deploy changes:

- `caddy` becomes a compose service (`saas-caddy`, `caddy:2.11.4-alpine`), with the
  Caddyfile from the repo and the **existing** `caddy_data` volume (external, so
  the Let's Encrypt certificates are reused).
- `api-gateway` no longer publishes 8080 on the host. Only Caddy publishes 80/443.
- `/api/v1/admin/*` answers 404 at Caddy for `api.logiclinkeg.tech`.
- Every container gets json-file log rotation (10 MB × 3) and a memory limit
  (728 MiB in total). Mongo runs with `--quiet` and a 0.25 GB WiredTiger cache.
  Redis runs with `maxmemory 32mb` and `noeviction`.
- deploy.yml removes the hand-started `saas-caddy` itself, once, right before
  `up -d` (section 2). The manual `docker rm -f` is only a fallback.
- deploy.yml no longer force-recreates every container on each deploy. It
  force-recreates everything only when the mTLS cert files were restored or
  regenerated in that run. It recreates only Caddy when the Caddyfile changed.

Downtime to expect on later deploys: the two cert-purge paths in deploy.yml
("Ensure Real mTLS Certificate Files") run `docker compose down`, which now also
stops Caddy. The public site is down from that point until the "Deploy Container
Services" step starts everything again. That covers the pre-flight, image pull and
`up`, normally a few minutes. If the pre-flight fails after a purge, everything,
Caddy included, stays down until the next successful run. Before this change,
Caddy kept answering 502 in that window. Now clients get connection refused.

Conventions: `$DEPLOY` is the runner's checkout of saas-core-deploy:

```bash
DEPLOY=/home/deploybot/actions-runner/_work/saas-core-deploy/saas-core-deploy
```

Run `docker compose` commands from `$DEPLOY` (compose project `saas-core-deploy`,
network `saas-core-deploy_saas-net`). Commands that need it are shown with `sudo`. Adjust
to the user you normally deploy with.

## 1. Pre-checks (read-only, any time before the merge)

1. The certificate volume exists. Write down its mountpoint:

   ```bash
   docker volume inspect caddy_data --format '{{.Name}} {{.Mountpoint}} {{.CreatedAt}}'
   ```

   If it does not exist: **stop**. The compose file declares it `external: true`, so
   `docker compose up` fails without it. Find the real volume name with
   `docker inspect saas-caddy --format '{{json .Mounts}}'` and report it before going on.

2. The hand-started Caddy is what we expect (not compose-managed, same mounts):

   ```bash
   docker inspect saas-caddy --format 'image={{.Config.Image}} project={{index .Config.Labels "com.docker.compose.project"}} restart={{.HostConfig.RestartPolicy.Name}}'
   docker inspect saas-caddy --format '{{range .Mounts}}{{.Type}} {{.Name}} {{.Source}} -> {{.Destination}}{{println}}{{end}}'
   ```

   Expected: `project=` empty. `caddy_data -> /data`.
   `/home/azureuser/saas-core-deploy/Caddyfile -> /etc/caddy/Caddyfile`. A `/config`
   mount may also show (often an anonymous volume). The new container uses a fresh
   named `saas_platform_caddy_config` volume. `/config` only holds Caddy's
   autosaved JSON config, so nothing is lost.

3. The deploy directory is where compose runs, and the running stack belongs to it:

   ```bash
   ls -la "$DEPLOY"
   docker inspect saas-api-gateway --format '{{index .Config.Labels "com.docker.compose.project"}} {{index .Config.Labels "com.docker.compose.project.working_dir"}}'
   ```

   Expected: project `saas-core-deploy`, working dir = `$DEPLOY`.

4. Live Caddyfile versus the one in this branch. Expected differences: comments and
   the `@admin` matcher only.

   ```bash
   diff /home/azureuser/saas-core-deploy/Caddyfile <path to this branch's infrastructure/deploy/Caddyfile>
   ```

5. Memory headroom and the current footprint. Each service must be well under its new
   limit (mongo 400 MiB, redis 48, auth 56, chat 56, user 48, gateway 32, caddy 40,
   notification 32, kyc console 16):

   ```bash
   free -m
   docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}'
   docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
   ```

   If any service is above about 70 % of its new limit, stop and raise that limit
   first. The worklog has the table and the reasoning.

6. Note the current certificate expiry, to compare after the cutover:

   ```bash
   echo | openssl s_client -connect api.logiclinkeg.tech:443 -servername api.logiclinkeg.tech 2>/dev/null | openssl x509 -noout -serial -enddate
   echo | openssl s_client -connect kyc.logiclinkeg.tech:443 -servername kyc.logiclinkeg.tech 2>/dev/null | openssl x509 -noout -serial -enddate
   ```

7. Find the temporary iptables rule for 8080 and write down its exact spec. It is
   removed in step 5 (Cleanup):

   ```bash
   sudo iptables -S DOCKER-USER | grep -n 8080
   sudo iptables -S INPUT | grep -n 8080
   ```

   Also check whether it was made persistent (`/etc/iptables/rules.v4`, `ufw`, or a
   systemd unit). This runbook does not know how it was added.

## 2. The name clash, and the cutover itself

The hand-started container is called `saas-caddy`, and so is the new compose
service. Compose cannot create its container while the old one exists.

Why the clash matters: tested locally (Docker 29.9.1, Compose v5.6.0), when
`docker compose up -d` hits a name conflict it exits 1. Containers it had already
(re)created for other services are left **Created but not started**. In production
that would leave every recreated service (at least `api-gateway`, whose ports
change) down, with the health checks and the automatic rollback skipped.

### Default: deploy.yml removes the hand-started Caddy itself

deploy.yml runs a cutover guard right before its main `docker compose up -d`, in
both the deploy step and the rollback step. It runs `docker rm -f saas-caddy` only
when **all** of these hold:

- the compose file being applied defines a `caddy` service;
- the compose project name could be determined;
- a container named `saas-caddy` exists;
- that container's `com.docker.compose.project` label is missing or differs from
  the current project (`saas-core-deploy`).

When it does, the job log shows `removing hand-started saas-caddy (one-time
cutover)`, followed by the label it found. A compose-managed `saas-caddy` (label
equal to the project) is never removed, so later deploys do nothing here.

So the cutover is:

1. Run the pre-checks (section 1). Pre-check 2 must show an empty `project=` for the
   current `saas-caddy`, which is what makes the guard act.
2. Merge the branch to `logic-exploitation`, then fast-forward `main` and push as usual.
3. `build-and-publish.yml` builds the images, then the update-deployment-repo job syncs
   `docker-compose.yml`, `Caddyfile` and `deploy.yml` into saas-core-deploy. That push
   starts `deploy.yml` on the VM runner.
4. In the "Deploy Container Services" step, check for the guard's log line. The public
   site is down from that `docker rm -f` until `up -d` starts the new `saas-caddy`
   (after the gateway and console it depends on). That window is expected to be
   seconds; it was not measured on the server.
5. Run the post-checks (section 3).

### Fallback: remove it by hand

Needed only if the guard did not remove the old container: no log line, plus a
`Conflict. The container name "/saas-caddy" is already in use` error in the deploy
step. One possible cause is the guard's warning `could not determine the compose
project name`. Then, in the deploy directory:

```bash
cd "$DEPLOY"
docker rm -f saas-caddy
docker compose up -d --remove-orphans
docker compose ps
```

Use `up -d` for the whole project, not `up -d caddy`. After a failed `up`, the
recreated services may be stopped, and `up -d caddy` starts only caddy and its
dependencies (gateway, console), not auth, user, chat or notification. Then run the
post-checks. The Actions run stays red. Re-run it from GitHub when convenient: it
is idempotent.

## 3. Post-checks

From **outside** the VM (laptop):

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://api.logiclinkeg.tech/health
curl -s -o /dev/null -w '%{http_code}\n' https://kyc.logiclinkeg.tech/
curl -s -o /dev/null -w '%{http_code}\n' https://api.logiclinkeg.tech/api/v1/admin/version-config
curl -sk --max-time 5 -o /dev/null -w '%{http_code}\n' https://<vm-ip>:8080/health
```

Expected: `200`; the console loads (open it in a browser too); `404`; and a timeout
or connection failure for the 8080 call (`000`).

To show the 8080 check passes because of compose, not the iptables rule, repeat
the last command after the iptables cleanup in section 5.

On the VM:

```bash
cd "$DEPLOY"
docker compose ps
docker inspect --format '{{.Name}} log={{.HostConfig.LogConfig.Type}} {{json .HostConfig.LogConfig.Config}} mem={{.HostConfig.Memory}} res={{.HostConfig.MemoryReservation}}' $(docker compose ps -q)
docker port saas-api-gateway
docker inspect saas-caddy --format '{{index .Config.Labels "com.docker.compose.project"}} {{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}'
docker exec saas-redis sh -c 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning CONFIG GET maxmemory*'
docker exec saas-mongo sh -c 'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.serverStatus().wiredTiger.cache[\"maximum bytes configured\"]"'
```

Expected:

- every container shows `log=json-file {"max-file":"3","max-size":"10m"}` and a non-zero `mem=`;
- `docker port saas-api-gateway` prints nothing;
- saas-caddy shows project `saas-core-deploy` and `caddy_data:/data`;
- Redis reports `maxmemory 33554432` and `maxmemory-policy noeviction`;
- Mongo reports `268435456` (0.25 GB).

Certificates were reused, not reissued:

```bash
echo | openssl s_client -connect api.logiclinkeg.tech:443 -servername api.logiclinkeg.tech 2>/dev/null | openssl x509 -noout -serial -enddate
docker logs saas-caddy 2>&1 | grep -iE 'obtain|issu|certificate' | tail -20
```

Expected: the same serial and expiry as pre-check 6. No "certificate obtained
successfully" line for these two domains. A new certificate is harmless, but it
means the volume was not reused, so investigate before cleaning up.

Watch for OOM kills during the first day:

```bash
docker inspect --format '{{.Name}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}' $(docker compose ps -q)
```

Any `oom=true`: raise that service's `mem_limit` in `infrastructure/deploy/docker-compose.prod.yml`
and deploy again. Do not edit `$DEPLOY/docker-compose.yml` by hand: the next sync overwrites it.

## 4. Using the admin API now

`/api/v1/admin/*` is no longer reachable from the internet. Call it on the VM,
inside the gateway container, which has `curl`. The gateway already holds
`ADMIN_API_TOKEN` in its environment (compose loads it from `/home/deploybot/.env`).
The single quotes make the container's shell expand it, so the token never
appears on the host command line or in history:

```bash
docker exec saas-api-gateway sh -c 'curl -sk -H "X-Admin-Token: $ADMIN_API_TOKEN" https://localhost:8080/api/v1/admin/version-config'
```

Update (JSON from a local file, sent on stdin):

```bash
docker exec -i saas-api-gateway sh -c 'curl -sk -X PUT -H "X-Admin-Token: $ADMIN_API_TOKEN" -H "Content-Type: application/json" --data-binary @- https://localhost:8080/api/v1/admin/version-config' < version-config.json
```

Fields: `latest_version`, `minimum_supported_version`, `enforce_minimum_version`,
`download_url` (https on `github.com` or `play.google.com` only).

If you prefer to read the token from `/home/deploybot/.env` explicitly:

```bash
ADMIN_API_TOKEN=$(sudo grep -E '^ADMIN_API_TOKEN=' /home/deploybot/.env | cut -d= -f2-)
docker exec -e ADMIN_API_TOKEN="$ADMIN_API_TOKEN" saas-api-gateway sh -c 'curl -sk -H "X-Admin-Token: $ADMIN_API_TOKEN" https://localhost:8080/api/v1/admin/version-config'
unset ADMIN_API_TOKEN
```

That variant briefly puts the token in the `docker exec` argument list, visible to
other users of the VM through `ps`. Prefer the first form.

The version store is still in memory (OPS-13, open product decision). A `PUT` is
lost whenever the gateway container restarts or is recreated.

## 5. Cleanup (only after every post-check passed)

1. Remove the temporary iptables rule. Use the exact spec you wrote down in
   pre-check 7, with `-A` replaced by `-D`. For example, if it printed
   `-A DOCKER-USER -p tcp -m tcp --dport 8080 -j DROP`:

   ```bash
   sudo iptables -D DOCKER-USER -p tcp -m tcp --dport 8080 -j DROP
   ```

   If the rule was persisted (pre-check 7), also remove it from that file or tool.
   Then repeat the outside 8080 check from section 3: it must still fail.

2. Remove the stale Caddyfile copy, after confirming no container mounts it:

   ```bash
   docker ps -aq | xargs -r docker inspect --format '{{.Name}} {{range .Mounts}}{{.Source}} {{end}}' | grep /home/azureuser/saas-core-deploy/Caddyfile
   ```

   Expected: no output. Then:

   ```bash
   sudo mv /home/azureuser/saas-core-deploy/Caddyfile /home/azureuser/saas-core-deploy/Caddyfile.pre-OPS-HARDEN.bak
   ```

   Delete the `.bak` after a few days without rollback. Keep it until then:
   section 6 needs it.

## 6. Rollback to the hand-started Caddy

Use this if the new Caddy does not serve (502s, TLS errors, wrong certificate):

```bash
cd "$DEPLOY"
docker logs saas-caddy --tail 100
docker rm -f saas-caddy
docker run -d --name saas-caddy --restart unless-stopped \
  --network saas-core-deploy_saas-net \
  -p 80:80 -p 443:443 -p 443:443/udp \
  -v /home/azureuser/saas-core-deploy/Caddyfile:/etc/caddy/Caddyfile \
  -v caddy_data:/data \
  caddy:2-alpine
```

The flags are the ones recorded for the original container. If you already moved the
Caddyfile in section 5, mount the `.bak` file instead. The gateway is reachable on
`saas-net` without a host port, so the old Caddyfile still works.

After a manual rollback, the **next deploy removes your hand-started Caddy again**.
The cutover guard sees a `saas-caddy` without this project's label and replaces it
with the compose one. If you want to keep the hand-started one, revert the
OPS-HARDEN Caddy commit before the next push to `main`.

If the automatic rollback in deploy.yml ever restores the pre-OPS-HARDEN
`docker-compose.yml` (no `caddy` service), it now skips `--remove-orphans` for that
run, so the compose-managed `saas-caddy` keeps serving. It also republishes 8080 on
the host, as the old file did. Re-add the iptables rule if you already removed it.
