# Lab 3 — Follow the Terraform workflow

This lab is the hands-on counterpart to Lesson 3 (`lessons/03-workflow-core.md`). The configuration is already written, so the "write" step is done for you. Your job is to prepare the working directory, check the configuration, preview the change, apply it, prove that a second run is a no-op, and clean up. That is the core workflow in miniature: every command has a visible effect, and every expected result can be checked without guessing.

The configuration declares three managed resources: a `random_pet` suffix, a primary S3 bucket named `lab3-demo-<suffix>`, and one extra bucket named `lab3-extra-0-<suffix>`. Both bucket names reference the same `random_pet.suffix.id`, so they share the suffix; the order of blocks in the file does not create that dependency, the reference does. The `extras` resource uses `count = 1`, which is why its only instance is addressed as `aws_s3_bucket.extras[0]`. The primary bucket has no index because it has no `count` or `for_each`. The two buckets are independent S3 buckets, not replicas; the second exists to make `count` and indexed addresses visible in the plan.

## What the files contain

| File | Role |
| --- | --- |
| `versions.tf` | Pins Terraform `1.12.0` exactly and requires AWS `~> 5.0` and random `~> 3.0`. |
| `providers.tf` | Configures AWS in `eu-west-1`. Credentials come from the environment or a profile; no keys are stored here. |
| `main.tf` | Declares `random_pet.suffix`, `aws_s3_bucket.primary`, and `aws_s3_bucket.extras` with `count = 1`. |
| `outputs.tf` | Empty. This lab declares no outputs, so `terraform output` prints nothing. |
| `.terraform.lock.hcl` | Records the provider selections. The existing file records AWS `5.100.0` and random `3.9.0`. |
| `terraform.tfstate` | Local runtime state, if generated; it is not included in a fresh clone. |

## How this lab differs from Lesson 3

The lesson and the lab teach the same workflow, but they are not the same configuration. Read the differences before copying a command.

| Topic | Lesson 3 | This lab |
| --- | --- | --- |
| Region | `us-east-1` | `eu-west-1` |
| Terraform version | `>= 1.12.0` | exact `1.12.0` |
| Random provider | `~> 3.6` | `~> 3.0`; the lock records `3.9.0` |
| Bucket addresses | `aws_s3_bucket.demo` in the base example | `aws_s3_bucket.primary` and `aws_s3_bucket.extras[0]` |
| Extra buckets | the challenge uses `count = 2` | `count = 1`, so only `extras[0]` exists |
| Outputs | the workflow examples do not depend on outputs | `outputs.tf` is empty |
| Drift | the lesson explains drift with a deletion example and practices a tag change | this lab uses a tag-only change; it does not ask you to delete a bucket |
| Replacement | the lesson demonstrates `-replace` | this lab explains it but does not recommend it on this bucket |
| Stale plan | the lesson appends a `tags` line to `main.tf` | edit the existing `tags` map; appending a second top-level `tags` argument would be invalid |

These differences matter. The exact version pin means Terraform `1.12.1` will fail `init`; a range would be more common in a real project, but the exact pin keeps this lab reproducible. The region determines where the buckets are created. `extras[1]` does not exist with `count = 1`, so the lesson's challenge command targets a resource this lab does not have. If you copy an address from the lesson, use `.primary` instead of `.demo` and `[0]` instead of `[1]`.

## Before you start: cost, credentials, and safety

The lab creates real S3 buckets in `eu-west-1`. An empty bucket has no standing charge of its own, but S3 is not free in general: storage, requests, versioning, and data transfer can be billed. The lesson's `$0.00` estimate assumes empty buckets destroyed promptly; it is not a guarantee. Use an isolated AWS account, check whether Free Tier applies to it, and plan to destroy the buckets when you finish.

Terraform must be exactly `1.12.0` because `required_version = "1.12.0"` is an exact constraint. The AWS provider is constrained to `~> 5.0`; the lock currently selects `5.100.0`. The random provider is constrained to `~> 3.0`; the lock selects `3.9.0`. Plain `terraform init` reuses the lock. A fresh init without the lock can select newer compatible versions, so keep `.terraform.lock.hcl` with the configuration. `fmt` and `validate` work without AWS credentials; `plan`, `apply`, and `destroy` need credentials with S3 permissions in `eu-west-1`.

Safety rules for this lab:

- Do not put access keys in `providers.tf`. Use the standard AWS environment variables or a named profile.
- Bucket names are globally unique. The random suffix reduces collisions but does not guarantee a free name. If apply fails with `BucketAlreadyExists`, change the prefix or the suffix length and plan again; do not try to take over an existing bucket.
- The configuration does not declare a bucket policy, ACL, public access block, versioning, encryption, or lifecycle rule. Account-level defaults apply. Do not put sensitive data in these buckets.
- State is local to this directory. Running Terraform from another directory uses a different state and may try to create duplicate buckets. Terraform does not encrypt local state for you, so keep `terraform.tfstate`, its backups, and any `*.tfplan` files private.
- Do not delete or edit state, restore a backup over the current state, or use `terraform state rm` to make cleanup appear to work. State is how Terraform knows which buckets it owns; deleting it does not delete the buckets, it orphans them.
- Do not run `-replace`, change the `bucket` argument, or delete a bucket in the console to "see what happens." Those actions destroy or bypass managed state and can lose data. A tag-only change is the safe way to see an in-place update.
- Do not run two Terraform commands against this directory at once. If a run is interrupted, rerun `plan` and `apply` so Terraform can reconcile; do not delete lock or state files.

## Run the workflow

Run every command from this directory. Terraform reads the `.tf` files here and uses the `terraform.tfstate` beside them.

### 1. Initialize the working directory

```sh
terraform init
```

Expected: Terraform initializes the local backend, installs or reuses the AWS and random providers, and ends with `Terraform has been successfully initialized!`. It creates `.terraform/` and may update `.terraform.lock.hcl` if a provider selection or platform hash is missing. It does not create AWS resources.

Why first: `init` resolves provider versions and prepares the backend. `validate` and `plan` need the provider schemas it installs. If `terraform version` is not exactly `1.12.0`, `init` stops with an `Unsupported Terraform Core version` error before downloading providers. Do not add `-upgrade` unless you intend to change the locked provider versions.

### 2. Check formatting and validity

```sh
terraform fmt -check
terraform validate
```

Expected: `fmt -check` prints nothing and exits `0` when the files are canonical; exit `3` means the files differ, not that the syntax is broken. If it prints filenames, run `terraform fmt`, review the diff, and rerun the check. `validate` prints `Success! The configuration is valid.`

Why these are not enough: `fmt` only changes presentation, and `validate` checks syntax, types, and references against the provider schema. Neither proves that AWS will accept the bucket names, that your credentials work, or that the service will accept the request. `validate` needs `init` first because it uses the downloaded provider schema. A formatted, valid configuration can still fail at plan or apply.

### 3. Preview the plan

```sh
terraform plan
```

With no managed resources in state, expect three additions and no changes or destructions:

```text
Plan: 3 to add, 0 to change, 0 to destroy.
```

The addresses are `random_pet.suffix`, `aws_s3_bucket.primary`, and `aws_s3_bucket.extras[0]`. Each should carry `+`. Bucket names and IDs should show `(known after apply)` because they depend on the random suffix, which does not exist until apply. There are no data sources, so `<=` should not appear.

Why read it: `plan` is the first cloud-aware check. It refreshes the state it has, compares the configuration with the current AWS objects, and shows the diff without applying it. The summary counts `random_pet.suffix` too; three additions does not mean three buckets. If the plan shows `0 to add`, you are probably in the wrong directory or using a state that already contains the resources. If it shows `-` or `-/+` for a bucket, stop and investigate before applying.

### 4. Apply and prove idempotence

```sh
terraform apply
```

Read the plan and type `yes` only when it matches the three additions above. Expected: `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.` Then:

```sh
terraform state list
terraform plan
```

`state list` should show the three addresses:

```text
aws_s3_bucket.extras[0]
aws_s3_bucket.primary
random_pet.suffix
```

The second `plan` should report `No changes. Your infrastructure matches the configuration.` Running `terraform apply` again should report `0 added, 0 changed, 0 destroyed`.

Why this is the meaningful test: a successful apply only proves that the API calls worked once. The second plan proves that Terraform can reconcile the configuration, the recorded state, and the refreshed AWS reality, and find no diff. That is idempotence. The random suffix does not change because its generated value is stored in state; Terraform does not regenerate it on every run. If the second plan shows a tag change, something modified the bucket outside Terraform. If it shows a bucket replacement, stop and investigate before applying.

### 5. Optional checks that do not risk the buckets

**Saved plan.** A saved plan lets you review and apply the same diff:

```sh
terraform plan -out=tfplan
terraform show tfplan
terraform apply tfplan
```

`terraform show` renders the binary plan in readable form; `apply tfplan` applies exactly that plan without the interactive prompt. If the plan is empty, apply reports no changes. If the configuration changed after the plan was written, `terraform apply tfplan` rejects it with `Saved plan is stale`; the rejected apply changes nothing. Try it by editing an existing tag value in `main.tf` after `plan -out`, then revert the edit and generate a fresh plan. Put the edit inside the existing `tags` block; appending a second top-level `tags` argument would be invalid HCL.

**Targeted plan.** This is a read-only way to see the dependency edge:

```sh
terraform plan -target=aws_s3_bucket.extras[0]
```

After apply, expect no changes for the targeted bucket and its `random_pet.suffix` dependency. From an empty state, expect two additions (`random_pet.suffix` and `extras[0]`) and no `primary`. Use `plan -target` for inspection; avoid `apply -target` here, because a partial apply leaves work for a later full apply and makes cleanup harder to reason about.

**Tag drift.** Change only the `Environment` tag of the primary bucket in the AWS console, then run `terraform plan`. Expect `~ aws_s3_bucket.primary` and a tag change; the bucket is updated in place, not replaced. `terraform apply` restores the value in your configuration. If you want to accept the manual value into state instead, `terraform apply -refresh-only` records reality but does not change AWS; a later plan will still propose the configured value. Do not delete the bucket to test drift.

**Read the generated names.** Because `outputs.tf` is empty, `terraform output` prints nothing. After apply, use the read-only console:

```sh
terraform console
> aws_s3_bucket.primary.bucket
> aws_s3_bucket.extras[0].bucket
```

The names are environment-specific. Do not copy them into code or use them as fixed identifiers.

### 6. Destroy and verify cleanup

```sh
terraform plan -destroy
terraform destroy
```

Review the destroy plan; it should list the same three addresses with `-`. Type `yes` only after checking that no unrelated resources appear. Expected: `Destroy complete! Resources: 3 destroyed.` The three include `random_pet.suffix`; it has no AWS object, but Terraform removes it from state. Then:

```sh
terraform state list
```

Expected: no output. The state file remains, now with no resources; that is normal. Verify in the AWS console or CLI that both buckets are gone from `eu-west-1`.

Why cleanup can fail: the configuration does not set `force_destroy`, so Terraform refuses to delete a bucket that still contains objects, versions, or delete markers. If `destroy` reports `BucketNotEmpty`, remove those objects with a reviewed process and rerun `destroy`. Do not enable `force_destroy` just to silence the error, and do not delete state to make the error disappear. If you delete a bucket manually first, Terraform may propose recreating it on the next plan because the configuration still declares it. To repeat the lab later, run `apply` again from this directory; with an empty state it creates a new suffix and new buckets.

## Practice

### Exercise — Complete the workflow and prove idempotence

**Objective:** Run the full workflow from initialization to cleanup and explain what each check proves.

**Steps:**
1. From this directory, run `terraform init`, `terraform fmt -check`, and `terraform validate`.
2. Run `terraform plan` and confirm the three addresses and the summary.
3. Run `terraform apply`, review the plan, and approve it.
4. Run `terraform state list` and a second `terraform plan`.
5. Run `terraform plan -destroy`, then `terraform destroy`, and verify the buckets are gone.

**Expected result:** With empty state, `init`, `fmt`, and `validate` succeed; the first plan shows `3 to add, 0 to change, 0 to destroy`; apply reports `3 added`; `state list` shows `aws_s3_bucket.extras[0]`, `aws_s3_bucket.primary`, and `random_pet.suffix`; the second plan reports no changes; destroy reports `3 destroyed` and `state list` is empty.

**Solution:** The detailed commands, expected output, and rationale are in "Run the workflow" above. The key is that the second plan — not the first apply — demonstrates convergence when nothing has changed.

**Criterios (criteria):** You can explain why there are three managed resources, why the bucket names are known only after apply, and why a second plan should not propose changes.

## Reading the plan symbols

| Symbol | Meaning | Where it appears here |
| --- | --- | --- |
| `+` | create | first plan: all three resources |
| `~` | update in place | a tag change on the primary bucket |
| `-` | destroy | `plan -destroy` and cleanup |
| `-/+` | destroy and recreate | changing the `bucket` argument or forcing `-replace`; avoid it here |
| `<=` | read a data source | not used; this lab has no data sources |

`-/+` is the symbol to treat as a warning in this lab. The bucket name is immutable in S3, so changing `bucket` forces replacement: Terraform would destroy the existing bucket and create a new one. With an empty bucket that may look harmless, but it is still destructive, and the old name may not be immediately reusable. Lesson 3 demonstrates `-replace`; this lab deliberately does not ask you to run it. If you want to see replacement safely, use a disposable resource in a separate configuration.

## Common failure modes

- **`Unsupported Terraform Core version`.** The pin is exact. Install `1.12.0` or change the constraint deliberately in a copy; do not assume `1.12.1` is accepted.
- **`BucketAlreadyExists`.** S3 names are global. Change the prefix or increase `random_pet` length, then run a fresh plan. Do not try to claim an existing bucket.
- **`No valid credential sources` or `AccessDenied`.** Configure the AWS environment or profile and confirm the identity can create, read, tag, and delete buckets in `eu-west-1`. Do not put keys in the configuration.
- **`BucketNotEmpty` during destroy.** Remove objects, versions, and delete markers with a reviewed process, then rerun `destroy`. Do not delete state or enable `force_destroy` blindly.
- **`Saved plan is stale`.** A `.tf` file or the state changed after `plan -out`. Revert the test edit and generate a fresh plan; the rejected apply changed nothing.
- **An interrupted apply.** Rerun `terraform plan` and `terraform apply`; Terraform will converge. Do not delete state or lock files to "reset" the run.

## Check your understanding

1. **Why does the first plan say three additions when there are only two buckets?**
   Terraform counts every managed resource, including `random_pet.suffix`. It is not an AWS object, but it is created and stored in state.

2. **Why does the second plan report no changes even though `random_pet` could generate a new name?**
   The generated suffix is stored in state. Terraform reuses it; it does not regenerate the pet on every run. The second plan proves idempotence.

3. **What does `terraform validate` not prove?**
   It does not prove that AWS will accept the bucket names, that credentials and permissions are sufficient, or that the apply will succeed. It only validates syntax, types, and references against the provider schema.

4. **Why is `-replace` a poor test for this lab?**
   It destroys and recreates the bucket. That can lose objects or versions, and it is not necessary to learn the workflow. Use a tag-only change to see `~`, and leave replacement for a disposable resource.

5. **What happens if you delete `terraform.tfstate` while the buckets exist?**
   Terraform loses the mapping to those buckets. A later plan may propose creating new buckets, and `destroy` will not remove the existing ones. The buckets become orphaned and may keep costing money.

## Verification

This guide was written from static inspection of the configuration and lock file. No `terraform` command, AWS call, or resource change was executed for this documentation. Expected outputs follow Terraform `1.12.0`; resource counts depend on your own state and inputs.
