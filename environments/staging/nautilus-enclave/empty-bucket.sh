#!/bin/bash
# Empty S3 bucket before deletion (handles versioned buckets)

set -e

PROFILE="${1:-zing-staging}"
BUCKET_NAME="zing-enclave-artifacts-staging"

echo "🗑️  Emptying S3 bucket: $BUCKET_NAME"
echo "Using AWS profile: $PROFILE"
echo ""

# Check if bucket exists
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
  echo "✅ Bucket $BUCKET_NAME does not exist or is already deleted"
  exit 0
fi

echo "📋 Listing all objects and versions in bucket..."

# Delete all object versions (required for versioned buckets)
echo "Deleting all object versions..."
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --profile "$PROFILE" \
  --output json \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  > /tmp/delete-versions.json

# Check if there are any versions to delete
VERSION_COUNT=$(jq '.Objects | length' /tmp/delete-versions.json)

if [ "$VERSION_COUNT" -gt 0 ]; then
  echo "Found $VERSION_COUNT object versions to delete"
  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --profile "$PROFILE" \
    --delete file:///tmp/delete-versions.json \
    --output json | jq -r '.Deleted[] | "Deleted: \(.Key) (version: \(.VersionId))"'
else
  echo "No object versions found"
fi

# Delete all delete markers (required for versioned buckets)
echo ""
echo "Deleting all delete markers..."
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --profile "$PROFILE" \
  --output json \
  --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  > /tmp/delete-markers.json

MARKER_COUNT=$(jq '.Objects | length' /tmp/delete-markers.json)

if [ "$MARKER_COUNT" -gt 0 ]; then
  echo "Found $MARKER_COUNT delete markers to remove"
  aws s3api delete-objects \
    --bucket "$BUCKET_NAME" \
    --profile "$PROFILE" \
    --delete file:///tmp/delete-markers.json \
    --output json | jq -r '.Deleted[] | "Removed delete marker: \(.Key) (version: \(.VersionId))"'
else
  echo "No delete markers found"
fi

# Also try the simpler method (works for non-versioned objects)
echo ""
echo "Deleting remaining objects..."
aws s3 rm s3://"$BUCKET_NAME"/ --recursive --profile "$PROFILE" || true

# Verify bucket is empty
echo ""
echo "🔍 Verifying bucket is empty..."
REMAINING=$(aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --profile "$PROFILE" \
  --output json \
  --query 'length(Versions) + length(DeleteMarkers)')

if [ "$REMAINING" -eq 0 ]; then
  echo "✅ Bucket is now empty and ready for deletion"
else
  echo "⚠️  Warning: Bucket still contains $REMAINING items"
  echo "You may need to run this script again or manually clean up"
fi

# Cleanup temp files
rm -f /tmp/delete-versions.json /tmp/delete-markers.json

echo ""
echo "✅ Bucket emptying completed"

