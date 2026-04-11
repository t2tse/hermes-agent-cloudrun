#!/bin/bash
set -e

REGION="${REGION:-us-central1}"
PROJECT_ID="${PROJECT_ID:?Set PROJECT_ID environment variable}"
REPOSITORY="hermes-agent"
IMAGE_NAME="hermes"
TAG="latest"
SERVICE_ACCOUNT="hermes-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com"

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${TAG}"

echo "Building and pushing Hermes Agent image using Cloud Build..."
gcloud builds submit \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --config=/dev/stdin \
  --service-account="projects/${PROJECT_ID}/serviceAccounts/${SERVICE_ACCOUNT}" \
  --default-buckets-behavior=regional-user-owned-bucket . <<EOF
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '--no-cache', '-t', '$IMAGE_URI', '.']
images: ['$IMAGE_URI']
EOF

echo "Done! Image pushed to $IMAGE_URI"
