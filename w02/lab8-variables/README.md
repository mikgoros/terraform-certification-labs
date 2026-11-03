# Lab 8 — Inputs, validation, and sensitive values

The same resource definitions can describe different environments without copy-paste. That only works when the differences live in inputs, the repeated calculations live in locals, and the results you need later are exposed as outputs. This lab builds a small VPC, EC2, and S3 stack that way. It also adds a validation rule for the environment name and uses a placeholder token to show what `sensitive` does — and what it does not do. Along the way, you will test Terraform's variable precedence instead of only memorizing the table.

One property of this lab matters before anything else: it is a single root module with one state. Changing `environment` changes the same resources; it does not create a second environment alongside the first. Use plans to compare `dev` and `prod`, and read the plan symbols before applying. Separate environments need separate state — separate directories, workspaces, or backends — and this lab sets up only one.

## Prerequisites and safety

Use Terraform 1.12.0 or newer, provider registry access, and AWS credentials with permissions for the VPC, EC2, S3, and the data sources in `main.tf`. The provider region comes from `var.region` and defaults to `us-east-1`. Even `terraform plan` reads AWS: it calls `aws_caller_identity`, lists Availability Zones, and searches for an Amazon Linux 2023 AMI. Without credentials, the plan fails before it can show the resources.

Applying creates real resources: a VPC, a public subnet, an internet gateway, a route table, a security group, a `t3.micro` instance, an EBS root volume, a public IPv4 address, and an S3 bucket. Charges may apply. The security group allows HTTP on port 80 from `0.0.0.0/0`, and no application is installed on the instance. Treat this as an isolated learning account exercise, not a production security baseline. Bucket names are globally scoped; the account ID suffix makes a collision unlikely, but a bucket left over from an earlier run can still block the next apply.

The lab is deliberately small, but it is not a multi-environment deployment. If you apply `dev` and then apply `prod` from this directory, Terraform will propose changes to the same resources in the same state. Names that the provider treats as requiring replacement — the S3 bucket and the security group are the clearest examples — may be destroyed and recreated. The plan will tell you; do not assume that a second environment appears beside the first.

## How the pieces fit together

The flow is easier to remember as a sentence: values come in from outside, get calculated into reusable internal values, feed the resources, and leave through outputs.

```text
CLI flags, environment, tfvars
            │
            ▼
   variable "environment"        input contract
            │
            ▼
   locals { name_prefix, … }     derived values
            │
            ▼
   resources and data sources    AWS
            │
            ▼
   output "environment_summary"  public result
            │
            ▼
   terraform output / another module
```

A useful mental model is a function: a `variable` is an argument, a `local` is an internal variable, and an `output` is the return value. The analogy is not exact, but it captures the direction of travel. Inputs are the part callers can change. Locals are implementation details the module owns. Outputs are the contract the module promises to expose.

| File | Responsibility |
| --- | --- |
| `versions.tf` | Terraform and AWS provider constraints |
| `providers.tf` | AWS provider, with `region = var.region` |
| `variables.tf` | The input contract: names, types, defaults, validation, sensitivity |
| `locals.tf` | Derived values shared by resources |
| `main.tf` | Data sources and the VPC, EC2, and S3 resources |
| `outputs.tf` | Values published after apply |

Only `variables.tf` and `outputs.tf` form the module's public boundary. `locals.tf` is internal by design: there is no flag or environment variable that can override a local. If a value must be chosen by whoever deploys the module, it belongs in `variables.tf`; if it is calculated from other values and reused, it belongs in `locals.tf`.

A `variable` block accepts `type`, `default`, `description`, `validation`, `sensitive`, and `nullable` (and `ephemeral` in newer Terraform). `depends_on`, `count`, `for_each`, `value`, and `provider` are not variable arguments. The lab uses the common ones and leaves `ephemeral` out because it is not needed for these tests.

## Inputs: the module's contract

The variables in `variables.tf` are intentionally a mixture of required, optional, validated, and sensitive inputs.

| Input | Type | Default | What it controls |
| --- | --- | --- | --- |
| `region` | `string` | `"us-east-1"` | AWS provider region; changing it changes where resources are created |
| `environment` | `string` | none — required | Names, tags, `is_production`, monitoring, and root volume size |
| `project` | `string` | `"tf-assoc"` | Prefix for resource names and tags |
| `instance_type` | `string` | `"t3.micro"` | EC2 instance type |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | VPC CIDR; the public subnet is derived from it |
| `extra_tags` | `map(string)` | `{}` | Additional tags merged into the common set |
| `admin_token` | `string` | placeholder | Demonstration value marked `sensitive` |

`environment` has no `default`, so Terraform treats it as required: a plan without a value prompts for one, and a non-interactive command fails. It also sets `nullable = false`, which rejects an explicit `null`. Those are two different protections. Removing the `default` makes the value mandatory; `nullable = false` says that even if someone supplies a value, `null` is not acceptable. `nullable = false` does not create a default and does not make an absent value valid.

The `validation` block is the only custom value check in the lab:

```hcl
variable "environment" {
  type     = string
  nullable = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}
```

The comparison is exact. `dev` passes; `Dev`, `DEV`, `dev ` (with a trailing space), and `invalid` fail. The error message is the one written in the file; Terraform adds its own preamble. Validation is a guard against bad input, not a security control, and it can only check what is knowable when the value is evaluated.

The other inputs deliberately have less protection. `project` is a plain string, so a value with uppercase letters, underscores, or other characters that are invalid in an S3 bucket name may survive `validate` and fail later when the bucket name is checked. `vpc_cidr` is a string consumed by `cidrsubnet`; a malformed CIDR fails when the local is evaluated. `instance_type` is passed to AWS, which may reject a type that does not exist in the region. That is a useful boundary to notice: a `validation` block is for invariants you can express locally, not a substitute for provider or API validation.

`admin_token` is marked `sensitive = true`. The default is an obvious placeholder, not a credential. The flag hides the value in normal CLI output, but the default is still visible in `variables.tf`, and any value used in a resource or output can still reach state. The next sections separate those behaviors carefully.

## Locals: one definition, many uses

`locals.tf` contains six derived values. Each one removes repetition or gives a name to a decision that would otherwise be scattered across resources.

```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Lesson      = "L8"
    },
    var.extra_tags
  )

  is_production      = var.environment == "prod"
  monitoring         = local.is_production
  root_volume_gb     = local.is_production ? 30 : 8
  public_subnet_cidr = cidrsubnet(var.vpc_cidr, 8, 0)
}
```

`name_prefix` is the single source for names such as `tf-assoc-dev-vpc`, `tf-assoc-dev-web`, and `tf-assoc-dev-assets-<account-id>`. Changing `project` or `environment` changes many names at once. That is the point of the local, but it also means a change can force replacement for resources whose names are immutable. The bucket and security group names are the ones to watch in this lab.

`common_tags` starts with four base tags and merges `var.extra_tags` on top. `merge` gives precedence to the later map, so a key in `extra_tags` overrides the same key in the base map. Resources that add a `Name` tag merge it after `common_tags`, so `Name` overrides everything there; the S3 bucket uses `common_tags` directly and has no `Name` tag in this configuration. This is a second, smaller precedence system nested inside the locals: base tags, then user tags, then the resource's own name. If `extra_tags` sets `Environment = "override"`, the tag says `override` while `name_prefix`, `is_production`, and the instance settings still use `var.environment`. Tags are metadata here, not control flow; do not expect them to change the derived logic.

`is_production` is true only for `"prod"`. `staging` is a permitted environment, but it is not production-like in this lab: it gets the same 8 GiB root volume and the same monitoring setting as `dev`. That is a deliberate simplification. If the business rule were "staging behaves like production," the boolean would need to change; the code is making a choice, not discovering one.

`monitoring` is an alias for `is_production`. It could be inlined, but the name documents what the setting means at the call site. `root_volume_gb` uses a ternary to choose between 30 GiB for production and 8 GiB otherwise. Detailed monitoring and the larger volume are the two places where `prod` costs more than the other environments.

`public_subnet_cidr` uses `cidrsubnet(var.vpc_cidr, 8, 0)`. With the default `10.0.0.0/16`, adding eight bits produces a `/24`, and network number 0 selects the first one: `10.0.0.0/24`. If you change `vpc_cidr` to another valid `/16`, the subnet follows. If you pass something that is not a valid CIDR, the function fails during evaluation; there is no `validation` block protecting this input.

Locals are evaluated lazily: a local that nothing references is not calculated. They may reference variables, data sources, resources, and other locals, but cycles are rejected. Several `locals` blocks can coexist in one module as long as no name is repeated. The reference is always singular — `local.name_prefix`, never `locals.name_prefix`.

## Outputs: what the module publishes

The outputs are the values you or another configuration would consume after apply. In a root module, they are printed by `terraform apply` and read with `terraform output`. In a child module, an output is the only way to expose a resource attribute to the parent; an attribute that is not exported is invisible from outside.

| Output | Value | Purpose |
| --- | --- | --- |
| `instance_id` | EC2 instance ID | Identify the instance |
| `public_ip` | Public IPv4 address | Reach or inspect the instance |
| `vpc_id` | VPC ID | Identify the network |
| `assets_bucket` | S3 bucket name | Identify the bucket |
| `environment_summary` | Object of environment, region, instance type, production flag, and volume size | Debug the effective configuration |
| `admin_token_echo` | The sensitive token | Demonstrate propagation and redaction |
| `web_url` | `http://<public-ip>` | Show the address the instance would use |

`environment_summary` is the most useful output for learning. It aggregates inputs and derived locals, so it answers "what did this configuration actually decide?" without reading the plan. It is an object, not a string: `terraform output environment_summary` prints it as HCL, `terraform output -json` produces structured data, and `terraform output -raw environment_summary` fails because `-raw` only works for strings.

`admin_token_echo` exists to make sensitivity visible. It is marked `sensitive = true` because its value comes from a sensitive variable. Without that mark, Terraform would refuse to expose it and would stop with `Output refers to sensitive values`. The mark is required for the output, not optional decoration. The value is still stored in state; the output section below shows how to prove that without printing the token.

`web_url` is a string and has a `precondition`:

```hcl
output "web_url" {
  value       = "http://${aws_instance.web.public_ip}"
  description = "URL de acceso a la instancia"

  precondition {
    condition     = aws_instance.web.public_ip != ""
    error_message = "La instancia no tiene IP pública: revisa map_public_ip_on_launch."
  }
}
```

The precondition checks one invariant: the instance has a non-empty public IP. It does not check that anything is listening on port 80, that the security group is reachable, or that the page returns a success status. When the IP is unknown during plan, Terraform defers the check until apply. An open HTTP port and an IP address do not add up to a working website. This configuration installs no web server and no application, so a request to `web_url` will normally fail; that is the expected result, not a bug in the output.

Outputs are only meaningful after apply. Before apply, `terraform output` has nothing to read, while `terraform plan` shows the planned output changes. `terraform output` without arguments prints all outputs; naming one prints that value; `-raw` removes quoting for shell scripts; `-json` produces machine-readable data. `-json` is convenient for `jq`, but do not assume it redacts sensitive values just because the normal display does. Treat any saved JSON output as potentially sensitive.

## Precedence: which value wins

Terraform can receive a variable value from several places at once. It does not merge them into a committee; it applies a fixed order, and the highest source that supplies a value wins. From highest to lowest:

| Rank | Source | Example | Notes |
| --- | --- | --- | --- |
| 1 | `-var` command-line flag | `terraform plan -var='project=cli-project'` | Highest in the exam-friendly summary |
| 2 | `-var-file` flag | `terraform plan -var-file=lab8-dev.tfvars` | An explicitly named file; the file is not auto-loaded without the flag |
| 3 | `*.auto.tfvars` | `zz-lab8.auto.tfvars` | Auto-loaded; with several files, the last in alphabetical order wins |
| 4 | `terraform.tfvars` | `terraform.tfvars` | Auto-loaded project defaults; one file (plus its `.json` variant) |
| 5 | `TF_VAR_<name>` | `TF_VAR_project=env-project` | Environment variable; the variable name and case must match exactly |
| 6 | `default` in the block | `default = "tf-assoc"` | Lowest; used only when nothing else supplies a value |

The auto-loading rule is narrower than many people expect. Terraform automatically reads `terraform.tfvars`, `terraform.tfvars.json`, and files matching `*.auto.tfvars` or `*.auto.tfvars.json` in the working directory. A file named `prod.tfvars` is invisible until you pass `-var-file=prod.tfvars`. A file named `prod.auto.tfvars` is auto-loaded, and if `aa.auto.tfvars` and `zz.auto.tfvars` both set the same variable, `zz` wins because it is later in lexical order. Prefixing auto files with numbers (`00-base`, `10-network`, `99-override`) makes the intended order obvious.

There is one nuance behind the table. Terraform processes `-var` and `-var-file` in the order they appear on the command line, and the last one wins. The exam-friendly rule is "`-var` has the highest precedence," and that is what you should remember for a multiple-choice question. In practice, put `-var` last if you want it to override a file:

```sh
terraform plan -var-file=lab8-dev.tfvars -var='project=cli-project'
```

### A precedence drill that does not create resources

Use `project` for this drill. It has a default, it is not required, and it feeds `local.name_prefix`, so you can evaluate the result in `terraform console` without creating resources. `environment` is passed with `-var` so Terraform does not prompt for it. `terraform console` loads variables and locals; it does not apply the configuration.

Start from the lab directory after `terraform init`. For the first result to be the plain default, make sure no `TF_VAR_project` is exported and no `terraform.tfvars` or `*.auto.tfvars` file is present. If you already have your own overrides, run the drill in a clean copy of the directory.

```sh
terraform console -var='environment=dev' <<< 'local.name_prefix'
# "tf-assoc-dev"
```

That is the `default` level. Now add an environment variable. The prefix applies only to this command, so it does not leak into later shells:

```sh
TF_VAR_project=env-project terraform console -var='environment=dev' <<< 'local.name_prefix'
# "env-project-dev"
```

Next, create a `terraform.tfvars` with a different project. This lab does not ship one. If one already exists in your copy, do not overwrite it: skip this rung or use a disposable copy of the directory. The other scratch file names below are also arbitrary; if any of them already exist, choose different names or use a disposable copy.

```sh
printf 'project = "file-project"\n' > terraform.tfvars
TF_VAR_project=env-project terraform console -var='environment=dev' <<< 'local.name_prefix'
# "file-project-dev"
```

The file wins over the environment variable. Now add two auto-loaded files. They are loaded in alphabetical order, so `zz` is applied after `aa` and wins:

```sh
printf 'project = "aa-project"\n' > aa-lab8.auto.tfvars
printf 'project = "zz-project"\n' > zz-lab8.auto.tfvars
terraform console -var='environment=dev' <<< 'local.name_prefix'
# "zz-project-dev"
```

A free-form `-var-file` beats the auto-loaded files. The file name is arbitrary; it is not auto-loaded, which is why the flag is required:

```sh
printf 'project = "varfile-project"\n' > lab8-dev.tfvars
terraform console -var='environment=dev' -var-file=lab8-dev.tfvars <<< 'local.name_prefix'
# "varfile-project-dev"
```

Finally, `-var` beats the file. Put it after `-var-file` to match the command-line-order behavior:

```sh
terraform console -var='environment=dev' -var-file=lab8-dev.tfvars -var='project=cli-project' <<< 'local.name_prefix'
# "cli-project-dev"
```

| Rung | What supplies `project` | `local.name_prefix` |
| --- | --- | --- |
| 1 | default | `"tf-assoc-dev"` |
| 2 | `TF_VAR_project` | `"env-project-dev"` |
| 3 | `terraform.tfvars` | `"file-project-dev"` |
| 4 | `*.auto.tfvars` (`zz` after `aa`) | `"zz-project-dev"` |
| 5 | `-var-file` | `"varfile-project-dev"` |
| 6 | `-var` | `"cli-project-dev"` |

The reason each row wins is the order in the table, not the name of the file or the fact that the value was exported. The environment variable is a lower-priority source even when it is exported, but in the drill above it is applied only to the command that demonstrates that level. `terraform.tfvars`, the auto files, the explicit `-var-file`, and the `-var` flag all sit above `TF_VAR_*`. If you export `TF_VAR_project` instead of prefixing a single command, unset it afterwards with `unset TF_VAR_project`.

Remove the drill files before moving on, using only the names you created. Do not remove a file you did not create, and do not use a broad wildcard:

```sh
rm -f aa-lab8.auto.tfvars zz-lab8.auto.tfvars lab8-dev.tfvars
# If you created terraform.tfvars for this drill, remove it too:
# rm -f terraform.tfvars
```

If you created `terraform.tfvars` and it existed before the drill, restore its previous contents instead of deleting it. Before applying anything, check that no scratch `terraform.tfvars` or `*.auto.tfvars` file is left; otherwise the next plan or apply will use the drill's project prefix. Remove the free-form `-var-file` scratch files as well, even though Terraform will not load them unless you name them.

If `terraform console` is unavailable in your environment, the same drill works with `terraform plan` by inspecting the resource `Name` tags and the `assets_bucket` output, but plan needs AWS credentials and reads data sources. The console version does not create resources and keeps the evaluation focused on variable resolution.

## Validation: what Terraform checks, and when

Run these checks after `terraform init` and after removing the precedence drill files. The first pair makes an important distinction: `validate` checks the configuration, while `plan` resolves input values and runs the custom validation.

**Test 1 — formatting and `validate` pass without a value for `environment`.**

```sh
terraform fmt -check
terraform validate
```

Expect both to succeed. `fmt -check` checks canonical formatting without rewriting files; if it lists a file, you can run `terraform fmt` to rewrite it, but review the diff first. `validate` checks syntax, references, and type constraints; it does not prompt for missing variables or evaluate a `validation` condition against a value it does not have. A successful `validate` is not proof that the inputs are usable.

**Test 2 — a non-interactive plan fails when the required variable is absent.**

```sh
terraform plan -input=false
```

Expect `No value for required variable` for `environment`. The variable has no `default`, which is what makes it required. `-input=false` turns the interactive prompt into a fast failure, which is the behavior you want in CI. If a `terraform.tfvars`, an auto file, or an exported `TF_VAR_environment` supplies `environment`, this test will not fail; remove the drill files or override the value deliberately.

**Test 3 — an invalid value is rejected by the validation block.**

```sh
terraform plan -var='environment=invalid'
terraform plan -var='environment=Prod'
```

Expect both commands to stop with `environment debe ser dev, staging o prod.` The condition uses `contains` with exact strings, so case and whitespace matter. `Prod` is not `prod`. The error message comes from `variables.tf`, not from AWS. If credentials are missing, configure them before interpreting the failure, so that the validation error is the one you actually see.

**Test 4 — `staging` is accepted but is not production.**

```sh
terraform plan -var='environment=staging'
terraform plan -var='environment=prod'
```

Both plans should be accepted. In the `staging` plan, expect names containing `staging`, the instance's `root_block_device.volume_size` set to `8`, and monitoring disabled. In the `prod` plan, expect names containing `prod`, `volume_size` set to `30`, and detailed monitoring enabled. The reason is the single boolean `local.is_production = var.environment == "prod"`; `staging` is a valid name but not a production-like branch.

**Test 5 — `extra_tags` overrides tags, not the derived logic.**

```sh
terraform plan -var='environment=dev' -var='extra_tags={"Environment"="override"}'
```

Expect the merged tags to show `Environment = "override"` while the resource names still use `dev`, `is_production` remains false, and the root volume remains 8 GiB. `merge` gives the later map precedence, so `extra_tags` wins over the base tags. The per-resource `Name` tag is merged after `common_tags`, so `Name` still wins over `extra_tags`. Tags are not read back into `local.is_production`; the logic reads `var.environment`.

**Test 6 — a bad CIDR fails in a local, not in a validation block.**

```sh
terraform plan -var='environment=dev' -var='vpc_cidr=not-a-cidr'
```

Expect a `cidrsubnet`/invalid CIDR error rather than a friendly validation message. `vpc_cidr` is only typed as `string`; the failure happens when `local.public_subnet_cidr` is evaluated. The same boundary applies to `project` and `instance_type`: there is no custom validation for them, so provider or API checks may be the first thing to object.

**Test 7 — `nullable = false` rejects an explicit null.**

This one needs a temporary variable file because the CLI is not the clearest way to pass a real `null`. Use a file name that does not already exist:

```sh
printf 'environment = null\n' > lab8-null.tfvars
terraform plan -var-file=lab8-null.tfvars
rm -f lab8-null.tfvars
```

Expect Terraform to reject the null value because `nullable = false`. This is different from Test 2: absence is handled by the missing default, while explicit null is handled by `nullable`. The file is not auto-loaded, so a stray copy will not affect later plans unless you pass it with `-var-file`; remove it anyway to keep the directory clean.

## Sensitive values: redaction in the CLI, not encryption at rest

`sensitive = true` is a display flag. It tells Terraform not to print the value in normal `plan`, `apply`, and `output` rendering. It does not encrypt the value, remove it from state, or prevent a deliberate read. The flag propagates: an expression derived from a sensitive value is also marked sensitive, and exposing it in an output without `sensitive = true` is an error.

Apply the lab with `dev` and inspect the outputs. Review the plan and approve it interactively; do not use `-auto-approve` for a first run.

```sh
terraform apply -var='environment=dev'
terraform output
terraform output admin_token_echo
```

Expect `admin_token_echo` to appear as `<sensitive>` in both listings. The other outputs — the instance ID, public IP, VPC ID, bucket name, summary, and URL — are visible. The planned output section should show the token as `(sensitive value)` rather than the placeholder.

Now read it deliberately:

```sh
terraform output -raw admin_token_echo
```

Expect the placeholder from `variables.tf`, not `<sensitive>`. `-raw` is designed for scripts and bypasses the normal display redaction. This is the central lesson: the flag protects against accidental exposure in logs and terminal output, not against someone who asks for the value. Do not run this command with a real credential, and do not paste the result into notes or chat.

The value is also in state. Use the output to search for it without printing the matching line:

```sh
token="$(terraform output -raw admin_token_echo)"
grep -F -c -- "$token" terraform.tfstate
unset token
```

Expect a count of at least 1. The state is local JSON and is not encrypted by `sensitive`. The count is enough to prove the point; do not print the matching line, and do not share the state file. If you changed `admin_token` to a different throwaway value, the same command searches for that value. If you used a real secret, stop and treat the state, its backups, and any saved plans as compromised.

To see the propagation guard, use a disposable copy of the lab rather than editing the original. Copy only the `.tf` files into an empty scratch directory; do not copy `terraform.tfstate`, its backup, or `.terraform/`, because those can contain the token and provider state. Remove `sensitive = true` from `admin_token_echo` in the copy, initialize it, and run:

```sh
terraform init
terraform plan -var='environment=dev'
```

Expect `Output refers to sensitive values` and a non-zero exit. Terraform is refusing to expose a value derived from a sensitive variable without an explicit sensitive output. Restore the copy or discard it. `nonsensitive()` can break the mark on purpose, but using it here defeats the guard and is not part of the exercise.

Two more limits are worth remembering. The default value in `variables.tf` is visible in the source; `sensitive` does not hide the file from anyone who can read the repository. And `terraform output -json` is machine-readable output; do not assume it redacts sensitive values just because the human-readable form does. Treat any JSON export, saved plan, state file, or state backup as sensitive. Encryption at rest is a backend concern, not a property of the `sensitive` flag; this lab uses local state, so there is no backend encryption to rely on.

The real fix for secrets is not a bigger `sensitive` flag. It is to avoid putting the secret in configuration at all, or to use a secrets manager together with ephemeral or write-only mechanisms. That is beyond this lab. For now, keep the placeholder, never commit state or variable files, and do not pass real secrets with `-var` where shell history or CI logs can capture them.

## Plan and apply: what to expect

With empty state, `terraform plan -var='environment=dev'` should propose one VPC, one public subnet, one internet gateway, one route table and association, one security group, one EC2 instance, and one S3 bucket. The plan also reads the account identity, the available Availability Zones, and the Amazon Linux 2023 AMI. The exact AMI ID and account ID will differ from another account; the shape of the plan should not.

The environment comparison is the part to read slowly:

| Setting | `dev` | `staging` | `prod` |
| --- | --- | --- | --- |
| Name prefix | `tf-assoc-dev` | `tf-assoc-staging` | `tf-assoc-prod` |
| `is_production` | `false` | `false` | `true` |
| EC2 detailed monitoring | off | off | on |
| Root volume | 8 GiB | 8 GiB | 30 GiB |
| Bucket name | `tf-assoc-dev-assets-<account-id>` | `tf-assoc-staging-assets-<account-id>` | `tf-assoc-prod-assets-<account-id>` |
| `Environment` tag | `dev` | `staging` | `prod` |

The names, tags, monitoring flag, and volume size all trace back to the same two inputs: `project` and `environment`. `staging` is accepted by validation, but it follows the non-production branch. That is why the table has two `false` rows and one `true` row, not three distinct behaviors.

If you apply `dev` and then plan `prod` in the same directory, the plan is not a second environment. It is a proposal to change the existing resources. The bucket name and security group name change, and those names are immutable in the AWS provider, so expect replacement markers for them. The instance tags and monitoring setting may update in place, and the root volume size may be modified. Read the symbols and the `# forces replacement` notes rather than assuming every change is safe. To keep both environments, use separate state; to compare them safely in this lab, plan both and apply only one, or destroy before switching.

After applying `dev`, inspect the results:

```sh
terraform output
terraform output -raw public_ip
terraform output -json | jq '.environment_summary.value'
terraform output -raw web_url
```

The first command shows the summary and redacts `admin_token_echo`. The second prints the instance's public address without quotes. The third is optional and needs `jq`; it extracts the summary object from the JSON form. The fourth prints the URL.

`terraform output -raw environment_summary` will fail because the summary is an object, not a string. That is expected. Use the normal form or `-json` for structured values.

Requesting `web_url` is likely to fail at the HTTP level:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' "$(terraform output -raw web_url)"
```

There is no web server on the instance, so expect a connection failure or `000`, not `200`. The security group permits port 80 and the subnet assigns a public IP, but an open port is not an application. The `web_url` precondition checks only that the IP is non-empty; it cannot tell whether anything is listening. The `assets_bucket` output is a bucket name, not a website endpoint; no bucket policy or static website configuration is added.

## Costs

The network building blocks in this lab have no separate hourly charge in this configuration: the VPC, subnet, internet gateway, route table, security group, and association do not create a NAT gateway, VPN, or load balancer. The billable parts are the compute instance, its storage, its public address, detailed monitoring in `prod`, and any S3 usage.

| Component | What drives the cost |
| --- | --- |
| `t3.micro` instance | Hourly compute; may be Free Tier eligible depending on account and region |
| EBS gp3 root volume | Per GB-month; 8 GiB in `dev`/`staging`, 30 GiB in `prod` |
| Public IPv4 | Hourly charge; AWS charges public IPv4 addresses, and Free Tier coverage is not universal |
| EC2 detailed monitoring | Enabled in `prod`; can add CloudWatch charges |
| S3 bucket | An empty bucket is negligible; storage and requests grow if you add objects |

For a short session, a reasonable estimate is roughly $0.02 without Free Tier, assuming a small instance and a 45-minute lifetime. With Free Tier, compute may be covered, but the public IPv4 address and detailed monitoring can still produce small charges. Treat the number as an order of magnitude, not a quote: prices vary by region and change over time. Leaving the instance and its public IPv4 running for a month costs dollars, not cents, and `prod` uses the larger volume. Plan-only comparisons do not create these charges, but they do read AWS and require credentials.

## Clean up

Destroy from the same directory, in the same region, with the values used for the last apply. The state is the source of truth for what exists; changing `region` makes the provider look in a different place and can leave the original resources orphaned. If you applied `dev`, use `dev`; if you applied `prod`, use `prod`.

The S3 bucket has no `force_destroy` setting, so Terraform cannot delete it while it contains objects. Empty it first, using the AWS CLI if it is installed or the console otherwise:

```sh
aws s3 rm "s3://$(terraform output -raw assets_bucket)" --recursive
```

If you enabled versioning or added object versions, remove the versions and delete markers too; `aws s3 rm --recursive` alone does not remove every versioned object. Then destroy:

```sh
terraform destroy -var='environment=dev'
```

Review the destruction plan and approve it. If you applied `prod`, use `prod` in the command. The plan should list the instance (including its root volume), bucket, security group, route table association, route table, internet gateway, subnet, and VPC. Verify in AWS that the instance is terminated, the root volume is gone, the bucket is gone, and the network resources are removed. The tags `Project`, `Environment`, and `Lesson=L8` help you find leftovers if something goes wrong, but do not delete unrelated resources that happen to share a tag.

If `destroy` fails with `BucketNotEmpty`, empty the bucket and run it again. If the state file is lost, do not delete the remaining resources blindly; inventory them by tag first, confirm they belong to this lab, and remove them deliberately. Deleting state before the resources are gone only makes the cleanup harder to audit.

Keep `terraform.tfstate`, `terraform.tfstate.backup`, any `*.tfvars` files, and saved plans private. The state can contain the token even though the output is marked sensitive, and a backup can contain the same value. The repository's ignore rules cover common state and variable files, but an ignore rule does not remove files that were already tracked or committed. Inspect what you publish, including history, before making the repository public.

## Self-check

1. **Why is `environment` required while `project` is not?** `environment` has no `default`, so Terraform needs a value; `project` has a default. `nullable = false` is a separate rule that rejects an explicit `null`.
2. **What does `nullable = false` change?** It rejects `null` as a value. It does not create a default and does not make an absent variable valid.
3. **If `TF_VAR_project=env-project` and `terraform.tfvars` sets `project = "file-project"`, which wins?** `terraform.tfvars`, because it is higher in the precedence order than `TF_VAR_*`.
4. **If `aa.auto.tfvars` and `zz.auto.tfvars` both set `project`, which wins?** `zz.auto.tfvars`, because auto-loaded files are applied in alphabetical order and the last one wins.
5. **Does `sensitive = true` encrypt the state?** No. It redacts normal CLI display. The state remains plaintext unless the backend provides encryption, and `terraform output -raw` can still print the value.
6. **Why does `staging` get an 8 GiB root volume?** `local.is_production` is true only for `prod`; `staging` follows the non-production branch of the ternary.
7. **Why is applying `prod` after `dev` not a second environment?** The lab has one root module and one state. The apply changes the same resources; some name changes force replacement. Separate environments need separate state.
8. **Why might `curl` to `web_url` fail even though the security group allows port 80?** No web server or application is installed. The precondition checks only that the public IP is non-empty, not that HTTP is healthy.

## Verification

These instructions and expected observations are based on static inspection of the configuration in this directory. The commands and the AWS deployment were not executed while writing this guide. Expected outputs depend on Terraform and AWS provider behavior, the target region, account settings, AMI availability, existing resources, and current prices. If you run the lab, record what you actually observe rather than treating the expectations above as recorded output.
