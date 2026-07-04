# Troubleshooting

## 1. Pod is in CrashLoopBackOff. What do you check?
- **Check Pod Status:** `kubectl get pods` for noticing number of restarts, age, namespace.
- **Describe the Pod:** `kubectl describe pod` for events, exit code, lastState, missing/wrong env vars, missing configmaps/secrets, verify image file permissions, check volume mounts(Common issues: PVC not bound, Wrong mount path, Permission denied), Check Liveness and Startup Probes
- **Check Resource Usage:** Look for the reason: OOMKilled using `kubectl top/describe pod`
- **Check Deployment Changes:** `kubectl rollout history deployment <deployment>` If a recent deployment caused the issue: `kubectl rollout undo deployment <deployment>`
- **Check Node Health:** `kubectl get nodes`

## 2. Deployment is successful, but app is not reachable. What do you check?
- **Verify the Pods are Running:** `kubectl get pods -o wide` and readiness probe status. 
- **Service and selector:** Service selectors match pod labels; `kubectl describe svc`
- **Check Endpoints:** `kubectl get endpoints`
- **Verify Labels and Selectors:** `kubectl get svc <web-app> -o yaml`
- **Verify the Container Port:** `kubectl describe deployment <web-app>`
- **Check Network Policies:** `kubectl get networkpolicy`
- **Ingress / Load Balancer:** correct host/path, TLS, backend service, and health checks. `kubectl get ingress` and `kubectl describe ingress`
- **Check Cloud Firewall / Security Groups:** For managed Kubernetes (AKS, EKS), verify: Firewall , Security Groups / NSGs, Load Balancer health, Public IP association

## 3. Difference between readiness and liveness probe?
- **Liveness probe:** determines if a container is still alive and healthy; detects if a container is dead/unrecoverable and should be restarted.
- **Readiness probe:** indicates if a container is ready to receive traffic; failing readiness removes pod from service endpoints.

## 4. Docker build works locally but fails in pipeline. Why?
- **Environment differences:** missing build args, secrets, or credentials in CI.
- **Cache and wrong build context:** large context, `.dockerignore` differences, or missing files not checked into repo.
- **Resource limits:** disk, memory, or network restrictions in CI environment.
- **Other Possible Reasons:** Different Docker version, OS differences, Permission issues, Missing files

## 5. Pipeline fails during Docker build. What do you check?
- **Build logs:** exact failing step and error message. Look for errors such as: COPY failed, RUN npm install failed, permission denied, no such file or directory, failed to solve
pull access denied
- **Credentials:** access to private base images or package registries.
- **Resource/timeouts:** CI runner quotas, disk space, or network timeouts.
- **Dockerfile assumptions:** platform/architecture mismatch or missing build args.
- **Verify Source Code Availability**
- **Verify Environment Variables and Secrets**
- **Check Dependency Installation**

## 6. Certificate renewal failed. What do you check?
- **Check the Error Logs:** kubectl logs <cert-manager-pod> -n cert-manager.
- **Check cert-manager:** `kubectl get certificate`; `kubectl get certificaterequest`; `kubectl get challenge`; `kubectl get order`
- **Rate limits and expiry:** CA rate limits or expired intermediate certs.
- **Ingress/ingress-controller:** Ensure the Ingress references the correct certificate and issuer.
- **Check Secrets:** `kubectl get secret`
- **Issuer misconfigured**

## 7. Ingress returns 502 or 504. What do you check?
- **Check if the Pods are Running:** `kubectl get pods -o wide`
- **Check the Service:** kubectl describe svc <service-name>
- **Check Endpoints:** `kubectl get endpoints`
- **Backend health:** service endpoints and pod readiness.
- **Ingress controller logs:** upstream connection errors or timeouts `kubectl logs -n ingress-nginx <ingress-controller-pod>`
- **Check Network Policies:** `kubectl get networkpolicy`
- **Check Readiness Probes:** `kubectl describe pod <pod-name>`
- **Timeouts and keepalive:** upstream timeout settings and long-running requests.
- **Network path:** service type, NodePort, or external load balancer health checks.
- **Check Resource Utilization:** `kubectl top pods` and `kubectl top nodes`

## 8. Vendor SFTP connection to port 22 times out. What do you check?
- **Connection timed out:** Possible reasons: Firewall blocking port or Vendor IP not allowlisted.
- **Network reachability:** telnet/nc from both sides, firewall rules, and NAT.
- **Port and service:** SFTP server listening on expected interface and port.
- **IP allowlists:** vendor IPs allowed in security groups and on-prem firewalls.
- **Routing and DNS:** correct destination IP and no intermediate proxy blocking.

## 9. Terraform plan wants to recreate the cluster. What do you check?
- **Drift and state:** compare real resources to state file; `terraform state list` and `terraform show`.
- **Review the terraform plan Output**
- **Review Provider Version Changes**
- **Manual portal changes**
- **Immutable fields:** provider or resource attribute changes that force replacement.
- **Provider versions and modules:** upgrades that change resource schemas.
- **Inputs and variables:** accidental changes to names, tags, or IDs.

## 10. How would you upgrade AKS/EKS safely?
- **Review Release Notes:** check breaking changes and deprecations.
- **Test in a Non-Production Environment:** Upgrade a development or staging cluster first.
- **Control plane first:** upgrade control plane, then node pools with rolling updates.
- **Drain and cordon:** drain nodes, verify workloads reschedule, monitor health and rollback plan.
- **Rollback Plan:** managed control plane upgrades generally can't be downgraded, follow recovery strategy: Restore applications from backups if needed, Roll back Helm releases if appropriate, Redeploy workloads.

## 11. Frontend loads, but backend API calls fail. What do you check?
- **CORS and auth:** CORS headers, tokens, and cookie domains.
- **Network path:** DNS, service endpoints, and ingress rules for API host/path.
- **Browser console and network:** error codes, request URL, and response body.
- **TLS and mixed content:** HTTPS frontend calling HTTP backend blocked by browser.
- **Verify the Backend API is Running:** `kubectl get pods`and `kubectl logs <backend-pod>`

## 12. Backend pod is running, but database connection times out. What do you check?
- **Check the Backend Logs:** `kubectl logs <backend-pod>`
- **Verify DB Connectivity from the Pod:** `kubectl exec -it <backend-pod> -- sh`. From the interactive terminal, run `nc -zv <db-host> 5432`
- **Network connectivity:** telnet/nc from pod to DB host/port.
- **Security groups and firewall:** DB allowlist includes pod/node IPs or VPC peering.
- **DB listener and credentials:** DB is accepting connections and credentials are valid.
- **Connection limits:** DB max connections or connection pool exhaustion.
- **Verify the Database is Running:** `kubectl get pods` ; `kubectl get svc`; `kubectl get endpoints`

## 13. Private DNS is not resolving database hostname. What do you check?
- **DNS zone and records:** correct A/CNAME/SRV records in private zone.
- **Verify Network Connectivity:** Ensure the application is running in the correct:VNet/VPC
Peered network, VPN-connected network, 
- **VPC/subnet association:** DNS zone linked to the correct network or VPC.
- **Resolver configuration:** pod/node DNS config, CoreDNS health, and forwarders.
- **Split-horizon or conditional forwarding:** ensure queries hit the private resolver.
- **Verify DNS Resolution from the Pod:**
- **Check Private Endpoint Configuration:** If the database uses a private endpoint: verify: private endpoint is healthy, private IP is assigned,DNS record points to the private IP

A common issue is the hostname resolving to a public IP instead of the private endpoint. 

## 14. How would you rotate database credentials safely?
- **Dual credentials:** create a new Database Credential, update app to support both, then revoke old creds.
- **Staged rollout:** update secrets in secret store, deploy config change, verify connections, then remove old secret.
- **Automate and monitor:** use secret manager with versioning and health checks; test rollback path.

## 15. Secrets were accidentally committed to GitHub. What do you do?
- **Identify the Exposed Secrets:** Determine exactly what was committed, for example:
    . Cloud access keys
    . Database passwords
    . API keys
    . SSH private keys
    . Kubernetes Secrets
    . Service account credentials
    . Certificates or tokens
- **Revoke immediately:** rotate or revoke the exposed credentials and keys.
- **Remove history:** purge secrets from git history (BFG or git filter-repo) and force-push. `git filter-re`
- **Invalidate tokens:** treat exposed secrets as compromised and rotate all dependent secrets.
- **Audit and notify:** check for misuse, update CI/CD secrets, and inform stakeholders per policy.
