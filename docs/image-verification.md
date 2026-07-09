# Image provenance: signatures, base images, scanning

Every Agent Shield image is:

- **Built on Chainguard** (`cgr.dev/chainguard/*`): minimal, distroless-style runtimes
  (python / node / static-for-Go), no shell, non-root — CVE surface kept near zero.
- **Signed with cosign** against a hardware-backed AWS KMS key (the private key never
  leaves KMS). Signatures are attached in-registry for both distribution channels
  (Docker Hub `g8rsecurity/agent-shield-*` and ECR `agent-shield/*`).
- **Scanned with Trivy** (Wolfi-aware) — nightly in CI and on release. Current 0.1.0
  status: **all 9 images CLEAN (zero CRITICAL/HIGH/MEDIUM CVEs)**. The mirrored/Hub
  copies are byte-identical (same digests), so one scan covers every channel.
  *Why Trivy and not registry-native scanning:* Amazon Inspector / ECR scanning cannot
  parse Wolfi (Chainguard's package database) and reports `UNSUPPORTED_IMAGE` — a scanner
  without Wolfi support silently scans nothing on these images. Trivy and Grype both
  support Wolfi; use one of those to re-scan on your side:

  ```bash
  trivy image docker.io/g8rsecurity/agent-shield-audit-store:0.1.0
  ```

## Verify a signature (customers)

Install [cosign](https://docs.sigstore.dev/cosign/system_config/installation/), then verify
against the Agent Shield public key ([`cosign.pub`](./cosign.pub), also provided in your POC
handoff package):

```bash
cosign verify --insecure-ignore-tlog --key cosign.pub \
  docker.io/g8rsecurity/agent-shield-audit-store:0.1.0
```

A valid result prints the verified claims, including the image digest. `--insecure-ignore-tlog`
is required because the signatures are key-based without a public transparency-log entry
(the flag name is alarmist — key verification itself is unaffected; it only skips the
Rekor-log lookup, which does not apply to private key-based signatures).

Mirrored images (e.g. copied into your own ECR with `scripts/mirror_images.sh`) keep the
same digest, so you can verify the digest you run matches the digest we signed even when the
signature artifact itself wasn't mirrored:

```bash
docker buildx imagetools inspect <your-registry>/agent-shield/audit-store:0.1.0
```

## Signing a release (vendor side)

```bash
# after the images are published to the registry:
cosign sign --yes --use-signing-config=false --tlog-upload=false \
  --key "awskms:///alias/agent-shield-cosign" <registry>/<repo>@<digest>
```

Sign by **digest**, and for Docker Hub sign the digest the *tag resolves to* (the OCI index),
not a per-platform child manifest — `cosign triangulate <ref>:<tag>` shows the resolved
digest in the expected signature location.
