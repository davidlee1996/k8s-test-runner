# AWS Setup for Week 3

Before any Week 3 code can run, you need an S3 bucket to store test results and an IAM user that can write to it. This walkthrough takes about 10 minutes.

**You'll create:**
- An S3 bucket for test results
- An IAM policy that grants only the specific permissions needed (principle of least privilege)
- An IAM user with that policy attached
- A long-lived access key (used in Phase 1; we'll switch to IRSA in Phase 2)

## Prerequisites

- AWS account with billing alert configured ($25/month threshold)
- AWS CLI installed and configured (`aws configure` already run)
- Region: we'll use `us-east-1` throughout (cheapest, simplest for portfolio work)

Verify your CLI is working:
```bash
aws sts get-caller-identity
```
Should print your AWS account ID and user ARN. If it errors, run `aws configure` and enter your credentials.

---

## Step 1: Create the S3 bucket

S3 bucket names must be globally unique. Use a suffix that distinguishes yours:

```bash
# Pick a unique suffix. Lowercase, no special characters.
BUCKET_NAME="k8s-test-runner-results-davidlee-$(date +%s)"

# Create the bucket in us-east-1
aws s3 mb "s3://${BUCKET_NAME}" --region us-east-1

# Save the bucket name — you'll need it everywhere
echo "${BUCKET_NAME}" > ~/.k8s-test-runner-bucket
echo "Bucket created: ${BUCKET_NAME}"
echo "Saved to: ~/.k8s-test-runner-bucket"
```

**Verify:**
```bash
aws s3 ls | grep k8s-test-runner-results
```

Should show your new bucket.

**Block public access** (S3 defaults to blocked, but verify explicitly — this is a senior-IC security habit):
```bash
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

## Step 2: Create the IAM policy

This is the single most important security step. We'll create a policy that allows **only** `PutObject` and `GetObject` on **only** this bucket. Nothing else.

**Why this matters:** if your access key ever leaks (accidentally committed, shared in a screenshot, etc.), the blast radius is "they can read/write objects in one S3 bucket." Not "they can spin up EC2 instances and rack up bills." Least privilege is not optional for portfolio code that lives on public GitHub.

Create the policy file:

```bash
BUCKET_NAME=$(cat ~/.k8s-test-runner-bucket)

cat > /tmp/k8s-test-runner-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowResultsUpload",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    },
    {
      "Sid": "AllowResultsRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
EOF

# Create the policy in AWS
aws iam create-policy \
  --policy-name k8s-test-runner-policy \
  --policy-document file:///tmp/k8s-test-runner-policy.json \
  --description "S3 access for k8s-test-runner portfolio project"
```

The output will include a `PolicyArn`. Save it:

```bash
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='k8s-test-runner-policy'].Arn" --output text)
echo "Policy ARN: ${POLICY_ARN}"
echo "${POLICY_ARN}" > ~/.k8s-test-runner-policy-arn
```

**Why two statements:**
- `PutObject` only on `bucket/*` — the runner only ever writes to keys inside the bucket
- `GetObject` + `ListBucket` on both the bucket and its contents — the aggregator needs to list objects in the bucket *and* read them. ListBucket requires the bucket ARN itself; GetObject requires the keys.

---

## Step 3: Create the IAM user

```bash
# Create the user with no console access (CLI-only)
aws iam create-user --user-name k8s-test-runner-uploader

# Attach the policy we just created
POLICY_ARN=$(cat ~/.k8s-test-runner-policy-arn)
aws iam attach-user-policy \
  --user-name k8s-test-runner-uploader \
  --policy-arn "${POLICY_ARN}"

# Create an access key
aws iam create-access-key --user-name k8s-test-runner-uploader
```

**The output of `create-access-key` is critical.** It looks like:

```json
{
  "AccessKey": {
    "UserName": "k8s-test-runner-uploader",
    "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
    "Status": "Active",
    "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    "CreateDate": "..."
  }
}
```

**Save both values immediately.** The secret key is shown ONLY at creation time — there is no way to retrieve it later. If you lose it, you have to delete the key and create a new one.

Write them to a local file (NOT committed):

```bash
cat > ~/.k8s-test-runner-credentials <<EOF
AWS_ACCESS_KEY_ID=<paste AccessKeyId here>
AWS_SECRET_ACCESS_KEY=<paste SecretAccessKey here>
S3_BUCKET=$(cat ~/.k8s-test-runner-bucket)
AWS_REGION=us-east-1
EOF

# Make it readable only by you
chmod 600 ~/.k8s-test-runner-credentials
```

Edit the file with your actual values:
```bash
nano ~/.k8s-test-runner-credentials   # or vim, or whatever editor
```

---

## Step 4: Verify everything works

Test that the credentials and policy work end-to-end before writing any code:

```bash
# Load the credentials into the current shell
source ~/.k8s-test-runner-credentials
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION

# Try to upload a test file
echo "test upload from $(date)" > /tmp/test.txt
aws s3 cp /tmp/test.txt "s3://${S3_BUCKET}/verification/test.txt"

# Try to download it back (tests GetObject permission)
aws s3 cp "s3://${S3_BUCKET}/verification/test.txt" /tmp/test-downloaded.txt
cat /tmp/test-downloaded.txt

# List the bucket (tests ListBucket permission)
aws s3 ls "s3://${S3_BUCKET}/verification/"

# Try to do something the policy DENIES — this should FAIL with AccessDenied
# (Trying to create a new bucket, which the policy doesn't permit)
aws s3 mb "s3://this-should-fail-${RANDOM}" 2>&1 | grep -i denied && echo "✓ Policy is correctly scoped — denial confirmed"
```

If all four commands behave as expected (three succeed, last one is denied), your AWS setup is correct.

---

## Step 5: Clean up the verification file

```bash
aws s3 rm "s3://${S3_BUCKET}/verification/test.txt"
```

---

## What you should have at this point

| Item | Location |
|---|---|
| S3 bucket name | `~/.k8s-test-runner-bucket` |
| IAM policy ARN | `~/.k8s-test-runner-policy-arn` |
| Access credentials | `~/.k8s-test-runner-credentials` (chmod 600) |
| AWS region | `us-east-1` |

Hand-verify each file exists and has the right content. The Week 3 code will read from these files (or expect the equivalent env vars exported into your shell).

---

## What this set up is, and isn't

**This is:**
- A scoped IAM user with permissions only for one S3 bucket
- A separate identity from your personal AWS account credentials
- Safe to use for portfolio code (low blast radius if leaked)

**This is NOT:**
- Production-grade. In Phase 2 (Week 5), we'll replace this with IRSA — IAM Roles for Service Accounts — which uses short-lived auto-rotated credentials issued by EKS's OIDC provider. That's the production pattern.
- A single sign-on integration, MFA-protected, or part of a real IAM strategy. For portfolio purposes, the access-key approach is the standard simple path.

**Why we're still doing the Phase 1 version this way:** Kind doesn't have an OIDC provider, so IRSA isn't an option for local development. The static credentials + Kubernetes Secret pattern is the standard fallback. The fact that we explicitly upgrade to IRSA in Phase 2 is itself a great interview talking point ("I started with static credentials in Phase 1 because the local cluster didn't support IRSA, then refactored to IRSA when moving to EKS in Phase 2").

---

## Troubleshooting

**`aws sts get-caller-identity` errors with "Unable to locate credentials":**
You haven't run `aws configure` yet, or your default credentials are missing. Run it:
```bash
aws configure
# AWS Access Key ID: <your personal access key>
# AWS Secret Access Key: <your personal secret>
# Default region name: us-east-1
# Default output format: json
```

**`create-bucket` fails with "BucketAlreadyExists":**
S3 bucket names are globally unique. Pick a different suffix.

**`create-policy` fails with "EntityAlreadyExists":**
You've run this step before. Either use the existing policy (look it up with `aws iam list-policies`) or delete it first:
```bash
aws iam delete-policy --policy-arn "$(cat ~/.k8s-test-runner-policy-arn)"
```

**`create-access-key` fails with "LimitExceeded":**
An IAM user can have at most 2 access keys. Delete an old one first:
```bash
aws iam list-access-keys --user-name k8s-test-runner-uploader
aws iam delete-access-key --user-name k8s-test-runner-uploader --access-key-id <old-key-id>
```

When you're done with this, you're ready to write the Week 3 code.