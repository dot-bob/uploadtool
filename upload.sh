#!/bin/bash

set +x # Do not leak information

RELEASE_NAME="continuous" # Do not use "latest" as it is reserved by GitHub
FULLNAME=SOME_FILE_NAME

if [ "$TRAVIS_EVENT_TYPE" == "pull_request" ] ; then
  echo "Release uploading disabled for pull requests, uploading to transfer.sh instead"
  for FILE in $@ ; do
    BASENAME="$(basename "${FILE}")"
    curl --upload-file $FILE https://transfer.sh/$BASENAME
    echo ""
  done
  exit 0
fi

if [ ! -z "$TRAVIS_REPO_SLUG" ] ; then
  # We are running on Travis CI
  echo "Running on Travis CI"
  echo "TRAVIS_COMMIT: $TRAVIS_COMMIT"
  REPO_SLUG="$TRAVIS_REPO_SLUG"
  if [ -z "$GITHUB_TOKEN" ] ; then
    echo "\$GITHUB_TOKEN missing, please set it in the Travis CI settings of this project"
    echo "You can get one from https://github.com/settings/tokens"
    exit 1
  fi
else
  # We are not running on Travis CI
  echo "Not running on Travis CI"
  if [ -z "$REPO_SLUG" ] ; then
    read -s -p "Repo Slug (GitHub and Travis CI username/reponame): " REPO_SLUG
  fi
  if [ -z "$GITHUB_TOKEN" ] ; then
    read -s -p "Token (https://github.com/settings/tokens): " GITHUB_TOKEN
  fi
fi

tag_url="https://api.github.com/repos/$REPO_SLUG/git/refs/tags/$RELEASE_NAME"
tag_infos=$(curl -XGET --header "Authorization: token ${GITHUB_TOKEN}" "${tag_url}")
echo "tag_infos: $tag_infos"

release_url="https://api.github.com/repos/$REPO_SLUG/releases/tags/$RELEASE_NAME"
echo "Getting the release ID..."
echo "release_url: $release_url"
release_infos=$(curl -XGET --header "Authorization: token ${GITHUB_TOKEN}" "${release_url}")
echo "release_infos: $release_infos"
release_id=$(echo "$release_infos" | grep "\"id\":" | head -n 1 | tr -s " " | cut -f 3 -d" " | cut -f 1 -d ",")
echo "release ID: $release_id"

if [ x"$release_id" != "x" ]; then
  delete_url="https://api.github.com/repos/$REPO_SLUG/releases/$release_id"
  echo "Delete the release..."
  echo "delete_url: $delete_url"
  curl -XDELETE \
      --header "Authorization: token ${GITHUB_TOKEN}" \
      "${delete_url}"
fi

echo "Checking if release with the same name is still there..."
echo "release_url: $release_url"
curl -XGET --header "Authorization: token ${GITHUB_TOKEN}" \
    "$release_url"

echo "Delete the tag..."
delete_url="https://api.github.com/repos/$REPO_SLUG/git/refs/tags/$RELEASE_NAME"
echo "delete_url: $delete_url"
curl -XDELETE \
    --header "Authorization: token ${GITHUB_TOKEN}" \
    "${delete_url}"

sleep 5
    
echo "Create release..."

if [ -z "$TRAVIS_BRANCH" ] ; then
  TRAVIS_BRANCH="master"
fi

if [ ! -z "$TRAVIS_JOB_ID" ] ; then
  BODY="Travis CI build log: https://api.travis-ci.org/jobs/$TRAVIS_JOB_ID/log.txt?deansi=true"
else
  BODY=""
fi

release_infos=$(curl -H "Authorization: token ${GITHUB_TOKEN}" \
     --data '{"tag_name": "'"$RELEASE_NAME"'","target_commitish": "'"$TRAVIS_BRANCH"'","name": "'"Continuous build"'","body": "'"$BODY"'","draft": false,"prerelease": true}' "https://api.github.com/repos/$REPO_SLUG/releases")

echo "$release_infos"

upload_url=$(echo "$release_infos" | grep '"upload_url":' | head -n 1 | cut -d '"' -f 4 | cut -d '{' -f 1)
echo "upload_url: $upload_url"

release_url=$(echo "$release_infos" | grep '"url":' | head -n 1 | cut -d '"' -f 4 | cut -d '{' -f 1)
echo "release_url: $release_url"

echo "Upload binaries to the release..."

for FILE in $@ ; do
  FULLNAME="${FILE}"
  BASENAME="$(basename "${FILE}")"
  curl -H "Authorization: token ${GITHUB_TOKEN}" \
       -H "Accept: application/vnd.github.manifold-preview" \
       -H "Content-Type: application/octet-stream" \
       --data-binary @$FULLNAME \
       "$upload_url?name=$BASENAME"
  echo ""
done

echo "Publish the release..."

release_infos=$(curl -H "Authorization: token ${GITHUB_TOKEN}" \
     --data '{"draft": false}' "$release_url")

echo "$release_infos"
