# Lab 6 — Configuration blocks, references, and read-only data

Seven configuration files in one directory produce three managed AWS objects, four read-only lookups, and five outputs. The small size is the point: you can follow every value from an input to a name, a tag, an API call, and an output without losing the thread in a large stack.

The lab is also deliberately incomplete as a network. It creates a VPC, one subnet, and an S3 bucket. It does not create an internet gateway, a route table, a NAT gateway, or any compute. That keeps the bill near zero and makes the difference between a `resource` and a `data` block the main event.

## Prerequisites

- Terraform 1.12.0 or newer. `versions.tf` requires at least 1.12.0, and the lock file records AWS provider 5.100.0.
- Network access for `terraform init` if the provider is not already cached. The lock file lets another machine resolve the same provider version.
- AWS credentials with permission to read the four data sources and to create and delete the VPC, subnet, and S3 bucket. Use the standard AWS credential chain; do not put credentials in this directory.
- An isolated learning account. The lab creates real resources, a failed apply can leave resources behind, and the account-derived bucket name can still collide with a name that already exists.
- The defaults target `us-east-1` and `dev`. You can override them with `-var`, but use the same values consistently within a run and during cleanup.

## What this lab builds

| Kind | Address | What it does |
| --- | --- | --- |
| managed resource | `aws_vpc.main` | VPC with CIDR `10.0.0.0/16` and DNS hostnames enabled |
| managed resource | `aws_subnet.public` | Subnet `10.0.1.0/24` in the first available Availability Zone |
| managed resource | `aws_s3_bucket.assets` | Bucket named from the environment and the caller's account ID |
| data source | `data.aws_caller_identity.current` | The account ID used in the bucket name |
| data source | `data.aws_region.current` | The region used by the provider |
| data source | `data.aws_availability_zones.available` | The list of available AZs for the subnet |
| data source | `data.aws_partition.current` | The AWS partition used in the ARN prefix output |
| output | `vpc_id`, `subnet_id`, `assets_bucket`, `region_in_use`, `arn_preffix` | Values published from state |

The value flow looks like this:

```text
var.region ──────────────────────────► provider "aws" ──► every AWS call
var.environment ──► local.name_prefix ──► S3 bucket name and Name tags
local.common_tags ─────────────────────► tags on all three resources
data.aws_caller_identity.current.account_id ──► S3 bucket name
data.aws_availability_zones.available.names[0] ──► subnet availability_zone
data.aws_region.current.name ──────────► output region_in_use
data.aws_partition.current.partition ──► output arn_preffix
aws_vpc.main.id ───────────────────────► subnet vpc_id, and therefore creation order
```

Every arrow is a reference. Terraform records references as edges in a dependency graph; it does not create resources in the order they appear in the files. That is why the subnet waits for the VPC even though nobody wrote “create the VPC first.”

The two block kinds look similar but have opposite responsibilities:

| | `resource` | `data` |
| --- | --- | --- |
| Owns a lifecycle | Yes: create, update, destroy | No: only read |
| Plan symbol | `+`, `~`, `-`, `-/+` | `<=` when it is a planned read |
| State mode | `managed` | `data` |
| Affected by `destroy` | Yes | No; the state entry is removed, nothing is deleted in AWS |
| Reference form | `aws_vpc.main.id` | `data.aws_region.current.name` |

A data source can still appear as “Reading…” during `plan` rather than as a `<=` action; the symbol depends on whether Terraform can read it during planning or must defer the read to apply.

## The grammar behind the files

HCL describes a desired state. You write what should exist, and Terraform compares that with the state file and the real API before deciding what to do. The order of files and the order of blocks inside a file are irrelevant; the graph built from references decides the order of operations.

Every block has the same shape:

```hcl
<block type> "<label>" "<label>" {
  argument = expression

  nested_block {
    ...
  }
}
```

The number of labels depends on the block type:

- `resource` and `data` take two labels: the type of object and a local name. `resource "aws_vpc" "main"` is referenced as `aws_vpc.main`.
- `provider`, `variable`, `output`, and `module` take one label.
- `terraform` and `locals` take none.

An *argument* is `name = expression` and is evaluated as one value. A *nested block* is `name { ... }` and can usually be repeated. `tags = { ... }` is an argument containing a map; `filter { ... }` inside a data source is a nested block. They look alike, but the provider schema decides which form is legal. Writing one where the other belongs produces an unsupported-argument or unsupported-block error.

Terraform reads every `.tf` file in the working directory, not only `main.tf`, and treats them as one configuration. Subdirectories are separate configurations unless they are called as modules. The split into `versions.tf`, `providers.tf`, and so on is a convention for humans; it has no effect on behavior. Native `.tf` is the only syntax used here; Terraform also accepts an equivalent `.tf.json` form, which is normally generated by a machine.

## The configuration, file by file

### `versions.tf` — the version and provider contract

```hcl
terraform {
  required_version = ">= 1.12.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

The `terraform` block configures Terraform itself, not an AWS object. `required_version` says the CLI must be at least 1.12.0; it does not pin an exact version. The `required_providers` map gives the provider a local name (`aws`) and declares which registry source and version constraint Terraform may use. `~> 5.0` means “5.x, but not 6.0.” The committed `.terraform.lock.hcl` records the version that was selected, currently 5.100.0, and the checksums for the provider package. Commit that lock file; do not edit it by hand.

There is no `backend` block. That means the state is local: Terraform writes `terraform.tfstate` and `terraform.tfstate.backup` in this directory. That is convenient for a single learner and unsuitable for a team, because the local backend does not provide shared locking across machines. A remote backend with locking is a later topic, not part of this lab.

`terraform init` reads this block, resolves the provider, and installs or reuses it under `.terraform/`. It does not create AWS resources.

### `providers.tf` — region, credentials, and scope

```hcl
provider "aws" {
  region = var.region
}
```

The provider block tells Terraform how to talk to AWS. The region comes from `var.region`, whose default is `us-east-1`. The block does not contain access keys, profiles, or role assumptions; the AWS provider uses its normal credential chain (environment variables, shared configuration, SSO, or an instance role, depending on where you run it). Keeping credentials out of the configuration is not optional hygiene: credentials in a `.tf` file are easy to commit and hard to rotate.

The provider is not a resource and does not appear in state. It is the adapter used by every resource and data source. Changing `region` changes the endpoint for all regional calls; it is not a harmless edit. Existing VPC and subnet IDs belong to the old region, so treat a region change as a different deployment and destroy the old one first, or keep separate state per region.

### `variables.tf` and `locals.tf` — inputs versus derived values

```hcl
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}
```

The file also contains `description` strings, which are documentation only and are omitted here for brevity. Variables are the configuration's inputs. The defaults make `terraform plan` work without flags. A command-line override such as `-var='environment=staging'` changes the value for that command only; it does not edit a file or persist. The next command without the flag uses `dev` again. Both variables are plain strings with no `validation` block, so Terraform accepts values such as `Prod` or `my_env` at this stage. Those values later become part of an S3 bucket name, where uppercase letters and underscores are invalid. The failure appears later, at plan or apply depending on where the provider catches it, not when the variable is read. That is a deliberate simplification for the lab, not a recommendation for shared configurations.

The locals are internal names for expressions:

```hcl
locals {
  name_prefix = "tf-assoc-l6-${var.environment}"
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Lesson      = "L6"
  }
}
```

`local.name_prefix` is a string derived from the input. `local.common_tags` is a map derived from the input and two constants. Locals are evaluated on every run and cannot be set with `-var`; if you need an input, use a variable. This is the practical boundary: variables are the public interface, locals are implementation details.

The resources use `merge(local.common_tags, { Name = ... })`. `merge` returns a new map. When keys collide, the later map wins; here the later map contributes `Name`, and `common_tags` itself is unchanged. The VPC and subnet therefore carry four tags, while the bucket carries only the three common tags and no `Name` tag. If you expect a `Name` tag on the bucket, the configuration does not provide one; the bucket name is its identifier.

### `data.tf` — reading AWS without owning it

```hcl
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_partition" "current" {}
```

Each block answers a question about the current AWS context:

- `aws_caller_identity` returns the account ID, caller ARN, and user ID for the credentials in use. Only `account_id` is consumed here, as the final segment of the bucket name. If you switch to credentials for another account, the bucket name changes and Terraform proposes a replacement.
- `aws_region` returns the region configured on the provider. It feeds the `region_in_use` output and is a useful check that the provider is using the region you think it is.
- `aws_availability_zones` returns the AZs for the current region. `state = "available"` filters out AZs that are not available to the account. The subnet takes `names[0]`, the first returned element.
- `aws_partition` returns `aws`, `aws-cn`, or `aws-us-gov` depending on the account and region. It feeds the ARN prefix output.

None of these creates, changes, or deletes anything. They are read-only lookups. Terraform reads them during `plan` because their arguments are already known. After apply, their results are stored in state with the `data.` prefix. During `destroy`, Terraform removes those state entries without making a delete call to AWS. A data source can still require permissions and network access: `plan` is not an offline operation, and a missing permission for the Availability Zone lookup can stop it. `terraform validate` is the offline check; `plan` is not.

`names[0]` is worth pausing on. It is the first element returned by the API, not a stable choice of “zone a.” The order can differ between accounts and regions, and the value can change if the set of available AZs changes. Because a subnet's Availability Zone is immutable, a changed first element can cause Terraform to replace the subnet even though the configuration did not change. The lab accepts that variability to avoid hardcoding an AZ. A production configuration that needs a stable zone should make the zone an explicit input or choose it deterministically.

Data sources are the right tool when the value genuinely varies by account or region. They are the wrong tool for a value you already know: every data source adds a read to the plan, a permission requirement, and a dependency on the API being reachable.

### `main.tf` — the managed resources and their graph

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-subnet-public" })
}

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name_prefix}-assets-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}
```

The VPC is a container. `cidr_block` defines its private address range; `enable_dns_hostnames` enables DNS hostnames for resources that use them. It does not create subnets, routes, or gateways. Those are separate objects, and this configuration creates only one subnet.

The subnet's `vpc_id` is the most important line in the file:

```hcl
vpc_id = aws_vpc.main.id
```

That reference does two jobs at once. It supplies the VPC ID, and it creates an implicit dependency edge from the subnet to the VPC. Terraform cannot know the ID until the VPC exists, so it creates the VPC first and the subnet afterward. If you replace the reference with a literal such as `vpc_id = "vpc-0123456789abcdef0"`, the value may still look plausible, but the edge disappears. The plan can look fine; apply then fails with an unknown VPC, or, worse, succeeds against a different VPC that happens to exist. A hardcoded ID is a design bug, not just a style issue.

The subnet's local name is `public`, and its `Name` tag ends in `-subnet-public`, but those are labels, not routing configuration. The configuration does not set `map_public_ip_on_launch`, does not create an internet gateway, and does not create or modify a route table. The subnet uses the VPC's main route table, which by default has only local routes. Nothing in this lab makes it reachable from the internet. Calling a resource `public` does not configure routing.

The bucket name is assembled from the environment prefix and the account ID:

```text
tf-assoc-l6-<environment>-assets-<12-digit-account-id>
```

S3 bucket names are globally unique within a partition, and the account ID makes accidental collisions unlikely, not impossible. If another account already owns the name, creation fails with a bucket-already-exists error. If your account owns the bucket but Terraform does not have it in state, creation fails with a bucket-already-owned error; importing it or choosing another name is the fix, not deleting data blindly. The bucket block declares only a name and tags. It does not declare versioning, a bucket policy, a public access block, lifecycle rules, encryption settings, or `force_destroy`. Account-level S3 defaults still apply, but this configuration is not a security baseline.

The graph is small enough to draw:

```text
data.aws_availability_zones.available ──► aws_subnet.public
aws_vpc.main ───────────────────────────► aws_subnet.public
local.name_prefix ──────────────────────► aws_s3_bucket.assets
data.aws_caller_identity.current ───────► aws_s3_bucket.assets
```

The VPC and the bucket are independent and can be created in parallel. The subnet waits for the VPC. Destroy runs in reverse: the subnet goes before the VPC, and the bucket is independent. The data sources have no destroy step.

This root module uses no `module`, `terraform_remote_state`, `count`, `for_each`, `depends_on`, or `lifecycle` block. A `module` block would load a reusable configuration, and its outputs would be referenced as `module.<name>.<output>`; a `terraform_remote_state` data source would read the outputs of another state. Neither pattern is demonstrated here, so do not read this configuration as an example of them. The entire lab is one root module with direct resources.

### `outputs.tf` — the public interface

```hcl
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "ID de la VPC creada"
}

output "subnet_id" {
  value       = aws_subnet.public.id
  description = "ID de la subnet pública"
}

output "assets_bucket" {
  value       = aws_s3_bucket.assets.bucket
  description = "Nombre del bucket de assets"
}

output "region_in_use" {
  value       = data.aws_region.current.name
  description = "Región resuelta en tiempo de ejecución (data source)"
}

output "arn_preffix" {
  value       = "arn:${data.aws_partition.current.partition}:s3:::"
  description = "Prefijo ARN de la partición AWS actual (aws, aws-cn, aws-us-gov)"
}
```

Outputs are how the configuration publishes values. They are stored in state and read back by `terraform output`; they are not recomputed from AWS at that moment. `vpc_id` and `subnet_id` are computed attributes: Terraform does not know them until the resources exist, so the plan shows `(known after apply)`. `assets_bucket` is known during planning because its inputs are known, and `region_in_use` and `arn_preffix` are known after the data sources are read.

The last output is spelled `arn_preffix`, with two `f`s. That is the actual name in the configuration, and it is part of the interface: scripts or other configurations that consume the output must use the same spelling. Renaming it to `arn_prefix` is a breaking change, not a cosmetic cleanup. The value is a prefix, not a complete ARN: in a standard commercial partition it is `arn:aws:s3:::`, and appending the bucket name produces the bucket ARN. In China or GovCloud the partition segment differs because the data source returns a different value.

Outputs can be marked `sensitive`, but none are here. That does not make state public-safe: state contains resource attributes and output values, and it may contain sensitive data in other configurations. Treat `terraform.tfstate` and its backup as private files regardless of how the outputs are marked.

## How a plan becomes an apply

1. `terraform init` loads `versions.tf`, resolves the AWS provider, and writes or reuses the lock file and `.terraform/` cache. No AWS resources are created.
2. `terraform plan` loads every `.tf` file in the directory and builds the graph. The four data sources have no dependency on managed resources, so Terraform reads them during planning. This is why a plan can require credentials even though it changes nothing.
3. Locals evaluate. `local.name_prefix` and the bucket name become known strings; the VPC and subnet IDs remain unknown until creation.
4. Terraform proposes three creates. The data reads and the known output values appear in the plan; the IDs appear as `(known after apply)`.
5. `terraform apply` creates the VPC and the bucket, then the subnet after the VPC's ID is available. The order comes from the graph, not from the order of blocks in `main.tf`.
6. Terraform evaluates the outputs and writes the result to state. A later plan refreshes the managed resources, reads the data sources again, and compares the result with the configuration.

A trimmed plan for an empty state looks like this:

```text
data.aws_caller_identity.current: Reading...
data.aws_region.current: Reading...
data.aws_availability_zones.available: Reading...
data.aws_partition.current: Reading...

Terraform will perform the following actions:

  # aws_s3_bucket.assets will be created
  + resource "aws_s3_bucket" "assets" {
      + bucket = "tf-assoc-l6-dev-assets-<account-id>"
      + id     = (known after apply)
    }

  # aws_subnet.public will be created
  + resource "aws_subnet" "public" {
      + availability_zone = "<first-available-az>"
      + id                = (known after apply)
      + vpc_id            = (known after apply)
    }

  # aws_vpc.main will be created
  + resource "aws_vpc" "main" {
      + cidr_block = "10.0.0.0/16"
      + id         = (known after apply)
    }

Changes to Outputs:
  + assets_bucket = "tf-assoc-l6-dev-assets-<account-id>"
  + arn_preffix   = "arn:aws:s3:::"
  + region_in_use = "us-east-1"
  + subnet_id     = (known after apply)
  + vpc_id        = (known after apply)

Plan: 3 to add, 0 to change, 0 to destroy.
```

The order of the data reads and the exact attributes shown vary by provider version; the counts and the known/unknown split are the stable observations. The plan is a proposal, not a promise. It can be offline-correct and still fail at apply because a bucket name is already taken, a quota is exhausted, a permission changes, or AWS rejects a value that Terraform could not validate without an API call.

## Checks and expected results

Terraform does not run a unit-test suite here. The checks below are observable behaviors, and each one tests a different layer: formatting, static coherence, the graph, API acceptance, state, outputs, and cleanup. Run them in order, and stop at the first unexpected result instead of applying on top of it.

### 1. Initialization and static checks

```sh
terraform init
terraform fmt -check
terraform validate
```

**Expected:** `init` succeeds and reports the provider installation or reuse; `fmt -check` exits 0 without changing files; `validate` reports a valid configuration.

**Why:** `init` resolves the provider and prepares `.terraform/`. `fmt -check` enforces the canonical style (two spaces, aligned `=`, no tabs) and is safe in CI because it does not rewrite anything; exit code 3 means at least one file would change. `validate` checks syntax, argument names, and references against the provider schema without calling AWS. It cannot catch an IAM problem, a bucket name collision, an unavailable AZ, or a CIDR that AWS will reject. Those appear at plan or apply.

If `fmt -check` fails, run `terraform fmt`, inspect the diff, and re-run the check. Do not format unrelated files that you did not intend to touch.

### 2. The first plan

```sh
terraform state list
terraform plan -out=lab6.tfplan
```

**Expected:** with empty state and default variables, four data reads and three creates: `Plan: 3 to add, 0 to change, 0 to destroy.` The bucket name, `region_in_use`, and `arn_preffix` are shown as known values; `vpc_id` and `subnet_id` are `(known after apply)`.

**Why:** empty state means Terraform owns nothing yet. The data sources are read because their arguments are known. The graph has no cycles and no existing objects to update, so every managed resource is a create. If `terraform state list` already shows resources, you are not starting clean; expect a different plan and inspect it before applying.

`-out` saves the exact plan you reviewed. Applying that file uses the variable values baked into it, so you do not have to repeat `-var` flags. A saved plan can contain sensitive values; keep it private and do not commit it. If you prefer not to save a plan, run `terraform plan` and then `terraform apply` with the same variable values.

A plan can fail while reading a data source if credentials are missing or lack permission. That is a credential or permission failure, not a syntax failure; `terraform validate` would still pass.

### 3. Apply and inspect the state

```sh
terraform apply lab6.tfplan
terraform state list
terraform state show aws_vpc.main
terraform state show data.aws_region.current
```

**Expected:** `Apply complete! Resources: 3 added, 0 changed, 0 destroyed.` The state list contains the three managed addresses and the four data sources:

```text
aws_s3_bucket.assets
aws_subnet.public
aws_vpc.main
data.aws_availability_zones.available
data.aws_caller_identity.current
data.aws_partition.current
data.aws_region.current
```

The exact order is not important. `terraform state show aws_vpc.main` shows the CIDR, tags, and ID; `terraform state show data.aws_region.current` shows the region attributes.

**Why:** state records both managed resources and the cached results of data reads. The `data.` prefix is how Terraform distinguishes the two. If you want to see the raw `mode` field, `terraform show -json` emits the state as JSON; `terraform state show` is a formatted view of the attributes and is not the best place to look for that field.

### 4. Idempotency and its limits

```sh
terraform plan
```

**Expected:** `No changes. Your infrastructure matches the configuration.` The data sources are read again, but no managed resource is updated.

**Why:** Terraform refreshes the managed objects, re-evaluates the configuration, and compares the two. If nothing drifted, there is no diff. A clean plan is not a complete audit: Terraform only compares the attributes it manages. If someone adds an S3 bucket policy or uploads objects outside this configuration, those objects are not in the configuration and may not appear in the plan. The bucket can be non-empty and still produce “no changes” for the bucket resource.

A data source can also change the plan without a code change. If the first available AZ changes, the subnet's `availability_zone` changes, and because that attribute is immutable, Terraform proposes a replacement. Computed values are inputs to the graph, not constants.

### 5. Outputs and the partition

```sh
terraform output
terraform output -raw region_in_use
terraform output -raw arn_preffix
terraform output -json
```

**Expected:** `region_in_use` equals `var.region` (with defaults, `us-east-1`). `arn_preffix` is `arn:aws:s3:::` in a standard commercial partition. `assets_bucket` matches `tf-assoc-l6-<environment>-assets-<account-id>`. `vpc_id` starts with `vpc-`, and `subnet_id` starts with `subnet-`.

**Why:** outputs are read from state, and the region and partition come from the data sources. In China or GovCloud, the partition segment is different; the output is designed to reflect the actual context rather than a hardcoded `aws`. `-raw` prints the value without quotes, which is useful in shell scripts. `-json` is the machine-readable form. If you ask for `arn_prefix` with one `f`, the command fails because the output name is `arn_preffix`; that is the interface working as declared.

### 6. A second environment

```sh
terraform plan -var='environment=staging'
```

**Precondition:** the default `dev` deployment has been applied, so state contains the three resources.

**Expected:** `Plan: 1 to add, 2 to change, 1 to destroy.` The VPC and subnet show in-place tag updates (`~`); the bucket shows a replacement (`-/+`).

**Why:** `environment` feeds both `local.name_prefix` and `local.common_tags`. The VPC and subnet `Name` tags and the common `Environment` tag change, and tags are mutable, so those are updates. The bucket's `bucket` argument changes, and an S3 bucket name cannot be changed in place, so the provider must create a new bucket and destroy the old one. Assuming the AZ list is stable, the account ID and the subnet's Availability Zone remain the same, so no other replacement is planned.

This check has several traps worth knowing:

- If state is empty, the same command plans three creates, not `1/2/1`; there is nothing to update or replace.
- If the new bucket name is already taken, the plan still proposes the replacement and apply fails. A plan cannot reserve a global name.
- If the old bucket contains objects, destroying it fails unless the bucket is emptied first. The replacement then stops partway; do not assume a failed apply left nothing behind.
- `-var` applies to that command only. If you apply `staging`, the state now describes staging resources. A later plan without the flag plans a return to `dev`, replacing the bucket again. For environments you intend to keep, use separate state or workspaces rather than ad-hoc `-var` values.

### 7. Two deliberate mistakes

The first mistake tests the data-source namespace. In `outputs.tf`, change the `region_in_use` value to:

```hcl
value = aws_region.current.name
```

Then run `terraform validate`. **Expected:** an error beginning `Reference to undeclared resource`, explaining that a managed resource `aws_region` named `current` has not been declared. Revert to `data.aws_region.current.name`.

**Why:** `aws_region` is a data source type, and its reference always carries the `data.` prefix. Without it, Terraform looks for a managed resource of that type and name, which does not exist. This is a static error: `validate` catches it before any AWS call.

The second mistake tests the graph. In `main.tf`, replace the subnet's `vpc_id` with a literal:

```hcl
vpc_id = "vpc-0123456789abcdef0"
```

`terraform validate` still passes because the value is a valid string. `terraform plan` may also look plausible. **Expected at apply:** if the VPC does not exist, AWS rejects the subnet with an unknown-VPC error; if the literal belongs to a different VPC, the subnet may be created in the wrong network. Revert to `aws_vpc.main.id` and confirm the plan returns to the original shape.

**Why:** the literal removes the reference edge. Terraform no longer knows that the subnet needs the VPC, so it no longer orders the two. The value being syntactically valid is not the same as the dependency being present. This is the practical meaning of an implicit dependency.

### 8. Destroy and verify

```sh
terraform plan -destroy
terraform destroy
terraform state list
```

**Expected:** the destroy plan has three destroy actions, all managed resources; data sources are not destroy targets. `terraform destroy` reports `3 destroyed`, and `terraform state list` prints nothing. `terraform output` no longer returns values.

**Why:** data sources are read-only; Terraform removes their state entries but never calls a delete API for them. The three managed resources have a lifecycle, so destroy removes them in reverse dependency order: the subnet before the VPC, with the bucket independent. If the bucket is not empty, the destroy fails at the bucket and the VPC may already be gone; the cleanup section explains how to handle that.

## What this lab deliberately leaves out

The omissions are part of the design, not hidden requirements:

| Area | Not declared here | Consequence |
| --- | --- | --- |
| Internet access | No internet gateway, route table, route, association, NAT gateway, or public IP setting | The subnet is isolated; `public` is only a label, not a route |
| Compute | No EC2 instance, Elastic IP, load balancer, or autoscaling group | No compute or public IPv4 charges |
| Network security | No security group, NACL, or VPC flow log | The default VPC security group exists but is unused; there is no traffic policy to study |
| Bucket lifecycle | No versioning, lifecycle rule, bucket policy, public access block, encryption configuration, or `force_destroy` | The bucket must be empty to destroy; account-level defaults still apply |
| Terraform features | No `module`, `terraform_remote_state`, `count`, `for_each`, `depends_on`, `lifecycle`, `import`, or `moved` block | The lab stays focused on the core blocks; those patterns are separate lessons |
| State backend | No `backend` block | State is local, with no shared lock across machines |
| Input validation | No `validation` block on either variable | Invalid environments reach S3 naming rules instead of failing early |

Two of those omissions deserve a sentence of context. A `module` block would call a reusable configuration; `source` is mandatory, and the module's outputs are referenced as `module.<name>.<output>`. A `terraform_remote_state` data source would read the outputs of another configuration's state; it is read-only, but it requires access to that state. This lab uses one root module and local state, so neither appears. If you are studying those patterns, this directory is not their example.

The `public` subnet is the most common source of confusion. A subnet becomes internet-accessible only when the route table associated with it has a route to an internet gateway (and the resources have public addresses or an Elastic IP, plus security rules that allow the traffic). This configuration creates none of those pieces. The name `aws_subnet.public` is a label chosen for the exercise, not a statement about reachability.

## Cost, safety, and cleanup

### Cost

| Declared component | Cost behavior |
| --- | --- |
| VPC and subnet | No separate hourly charge for the VPC or subnet itself |
| S3 bucket | No storage charge while empty; requests are billed separately, and you pay for stored objects and data transfer if you add or download data |
| Four data reads | No separate charge in normal use; standard API request or audit-logging costs, if any, are account-level |
| EC2, NAT gateway, Elastic IP, load balancer | Not created, so no compute, NAT, or public-address charges |

The expected bill for the declared resources is near zero, but that is not a guarantee. The usual hidden cost in a VPC lab is a NAT gateway; this lab does not create one. An empty bucket is cheap, but a bucket with objects, versions, or frequent requests is not free. Check your account and the current AWS pricing rather than treating “lab” as a synonym for “free.”

### State, credentials, and files

Terraform state is the record of what Terraform owns. It contains resource attributes, output values, and identifiers; in other configurations it can contain sensitive values even when no output is marked `sensitive`. The local `terraform.tfstate` and `terraform.tfstate.backup` in this directory are runtime artifacts, not source code. Do not commit them, paste them into a ticket, or share them in a screenshot. If this directory is part of a repository, confirm that state, backups, `.terraform/`, and saved plans are ignored and were never tracked. Adding an ignore rule does not untrack a file that is already committed.

The local backend has no shared lock across machines. Do not run two applies against the same state from different terminals or hosts. For a team, use a remote backend with locking; for this lab, one operator at a time is enough.

Credentials belong outside the repository. Use the AWS credential chain (environment variables, a profile, or SSO) and keep access keys out of `providers.tf`, `terraform.tfvars`, and the README. `.terraform.lock.hcl` is different: it contains the provider version and checksums, not credentials, and it should be committed so another machine resolves the same provider. `.terraform/` is a local cache and should not be committed.

A saved plan (`lab6.tfplan` or any other name) can contain values from the configuration and state. Keep it private and delete it when you no longer need it. A `terraform.tfvars` file can also contain values you do not want to publish; this lab does not commit one, but if you create one locally, inspect it before sharing the directory.

### Cleanup procedure

1. Save the identifiers and outputs you will need for verification:

   ```sh
   terraform output
   ```

2. If you uploaded objects, empty the bucket before destroying it. This deletes every object in the bucket, so use the bucket name deliberately:

   ```sh
   BUCKET="$(terraform output -raw assets_bucket)"
   aws s3 rm "s3://${BUCKET}" --recursive
   ```

   If versioning was enabled outside this configuration, also remove object versions and delete markers with the S3 API or the console. `aws s3 rm --recursive` on a versioned bucket adds delete markers; it does not remove the old versions.

3. Review the destruction plan:

   ```sh
   terraform plan -destroy
   ```

   Expect three destroy actions for managed resources and no data-source destroy actions. If the plan contains replacements or resources you did not expect, stop and inspect the state before applying it.

4. Destroy with the same region and environment values you used for the deployment. With the defaults, plain `terraform destroy` is enough:

   ```sh
   terraform destroy
   ```

   If you applied with flags, pass them again, or apply a saved destroy plan. The provider region matters most: destroying with a different region points the provider at the wrong endpoint. Using the same environment keeps names and tags consistent with what you reviewed.

5. Confirm that state is empty:

   ```sh
   terraform state list
   ```

   No output means Terraform no longer records any managed resources or data sources.

6. Verify in AWS, using the IDs and bucket name you saved in step 1:

   ```sh
   aws ec2 describe-vpcs --vpc-ids <vpc-id>
   aws ec2 describe-subnets --subnet-ids <subnet-id>
   aws s3api head-bucket --bucket <bucket-name>
   ```

   Expect `InvalidVpcID.NotFound`, `InvalidSubnetID.NotFound`, and a 404/`NoSuchBucket` response. A nonzero AWS CLI exit code is expected here; it is evidence that the resource is gone, not a failure of the cleanup.

7. Only after verification, remove local state, backups, and saved plans if you no longer need them. Never delete state while resources still exist: Terraform would lose track of them, and they could keep running and billing. If you want to keep evidence of the exercise, store it somewhere private rather than in the repository.

If destroy fails because the bucket is not empty, empty it and rerun. If a resource was deleted manually and the state is stale, run a plan to see what Terraform still believes it owns; do not delete the state file to make the error disappear. The tags `ManagedBy = "terraform"` and `Lesson = "L6"` are useful when looking for resources that outlived a failed cleanup.

## Self-check

1. **Why does `terraform plan` contact AWS even though it does not create anything?**
   It refreshes managed resources and reads data sources. The four data sources in this lab are resolved during planning, so the provider needs credentials and network access.

2. **Why is the bucket name known at plan time while the VPC ID is not?**
   The bucket name is built from a variable, a local, and the account ID, all known before creation. The VPC ID is a computed attribute returned by AWS after the VPC exists.

3. **What happens to `data.aws_region.current` during `terraform destroy`?**
   Nothing is deleted in AWS. Terraform removes the data source's state entry; data sources have no destroy lifecycle.

4. **Why does changing `environment` replace the bucket but only update the VPC and subnet?**
   The bucket name is immutable, so a new name requires a new bucket. Tags are mutable, so the VPC and subnet can be updated in place.

5. **Why is `aws_subnet.public` not actually public?**
   The word `public` is only a label (the local name and part of the `Name` tag). The configuration creates no internet gateway or route to one, does not set `map_public_ip_on_launch`, and does not modify the main route table.

6. **What does `merge(local.common_tags, { Name = ... })` do to `local.common_tags`?**
   It returns a new map with the `Name` key added or overridden. The original `common_tags` map is unchanged. VPC and subnet get the merged map; the bucket gets the original map without `Name`.

7. **Why is `terraform validate` not enough before applying?**
   It checks syntax, provider schema, and references without calling AWS. It cannot verify IAM permissions, bucket-name availability, AZ availability, CIDR acceptance, or quota limits.

8. **What must you do before destroying a bucket that contains objects?**
   Empty the bucket, and remove versions and delete markers if versioning was enabled. The bucket resource does not set `force_destroy`, so a non-empty bucket blocks destruction.

## Verification status

This guide was written by static inspection of `versions.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `data.tf`, `main.tf`, `outputs.tf`, and the committed `.terraform.lock.hcl`. No `terraform` command and no AWS CLI command was executed for this revision; no resources were created or deleted. Values shown as `<account-id>`, `<first-available-az>`, `<vpc-id>`, and `<bucket-name>` depend on the account, region, and run. The configuration declares Terraform `>= 1.12.0` and AWS provider `~> 5.0`; the lock file records provider `5.100.0`. A different provider version can change the exact plan output, so verify the plan in your own environment.

This README is self-contained. It does not link to course files or external documentation; everything it describes is in this directory or is standard Terraform and AWS behavior.
