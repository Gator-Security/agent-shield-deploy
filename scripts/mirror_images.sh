#!/usr/bin/env bash
# CUSTOMER-SIDE: mirror the Agent Shield images from the vendor's ECR into YOUR ECR, so
# your cluster pulls from your own registry (the Terraform/Helm default). Run this once
# before `terraform apply`, and again whenever you take a new release tag.
#
# Prerequisites:
#   - The vendor has granted your AWS account pull access (ask for it — one command on
#     their side), and told you their registry host + region.
#   - Your AWS credentials can create ECR repositories + push in your account.
#   - docker (or set CONTAINER_TOOL=podman).
#
# Usage:
#   scripts/mirror_images.sh <YOUR_REGION> <YOUR_ACCOUNT_ID> [TAG]
# Example:
#   scripts/mirror_images.sh us-east-2 123456789012 0.1.0
#
# Vendor source overrides (defaults below):
#   VENDOR_REGISTRY=<acct>.dkr.ecr.<region>.amazonaws.com VENDOR_REGION=<region>
set -euo pipefail

REGION="${1:?usage: mirror_images.sh <YOUR_REGION> <YOUR_ACCOUNT_ID> [TAG]}"
ACCOUNT="${2:?need your 12-digit AWS account id}"
TAG="${3:-0.1.0}"
DOCKER="${CONTAINER_TOOL:-docker}"

# The source registry your Agent Shield contact grants your account pull access to. They give
# you both values at onboarding — set them here (or export before running). Required: no default.
VENDOR_REGION="${VENDOR_REGION:?set VENDOR_REGION to the source registry region (e.g. us-east-2)}"
VENDOR_REGISTRY="${VENDOR_REGISTRY:?set VENDOR_REGISTRY to the source registry your Agent Shield contact provides}"
DEST_REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

SERVICES=(audit-store pdp registry egress identity compliance pep management-api ui)

echo "==> login: vendor registry (pull) + your registry (push)"
aws ecr get-login-password --region "$VENDOR_REGION" | "$DOCKER" login --username AWS --password-stdin "$VENDOR_REGISTRY"
aws ecr get-login-password --region "$REGION"        | "$DOCKER" login --username AWS --password-stdin "$DEST_REGISTRY"

echo "==> ensuring agent-shield/* repositories exist in ${REGION}"
for s in "${SERVICES[@]}"; do
  aws ecr describe-repositories --region "$REGION" --repository-names "agent-shield/$s" >/dev/null 2>&1 \
    || aws ecr create-repository --region "$REGION" --repository-name "agent-shield/$s" \
         --image-scanning-configuration scanOnPush=true >/dev/null
done

echo "==> mirroring ${#SERVICES[@]} images at tag ${TAG}"
for s in "${SERVICES[@]}"; do
  src="${VENDOR_REGISTRY}/agent-shield/${s}:${TAG}"
  dst="${DEST_REGISTRY}/agent-shield/${s}:${TAG}"
  echo "  ${s}: ${src} -> ${dst}"
  "$DOCKER" pull --platform linux/amd64 "$src" >/dev/null
  "$DOCKER" tag "$src" "$dst"
  "$DOCKER" push "$dst" >/dev/null
done

echo "==> verify"
fail=0
for s in "${SERVICES[@]}"; do
  d=$(aws ecr describe-images --region "$REGION" --repository-name "agent-shield/$s" \
        --image-ids imageTag="$TAG" --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || echo "")
  if [ -n "$d" ] && [ "$d" != "None" ]; then printf "  %-16s OK\n" "$s"; else printf "  %-16s MISSING\n" "$s"; fail=1; fi
done
[ "$fail" = "0" ] || { echo "ERROR: some images failed to mirror"; exit 1; }

echo "done. All 9 images available at ${DEST_REGISTRY}/agent-shield/*:${TAG}"
echo "Proceed with: cd terraform/eks && terraform apply   (image_tag = ${TAG})"
