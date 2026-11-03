# Lab 7 — Types, collections, and expressions

Terraform's type system is a contract between what a configuration declares and what it actually receives. A `number` rejects `"eighty"` before any AWS API call; a `set` refuses `[0]`; a `map` insists on a string key. This lab puts all three families in one configuration — primitives (`string`, `number`, `bool`), collections (`list`, `set`, `map`), and structural types (`object`, `tuple`) — and uses them in a VPC, three subnets, three S3 buckets, and three SSM parameters.

The goal is not to memorize a list of names. It is to predict what an expression returns, and why, before you run it. That prediction is what the exam and real configurations reward.

## What you will practice

- Classify a type as primitive, collection, or structural, and reject invented names such as `float`, `tree`, or `pair`.
- Read values by list index, set membership, map key, object attribute, and tuple position.
- Explain why a `set` cannot be indexed and why `for_each` needs a map or a set of strings.
- See `optional()`, `any`, `null`, and the `to*` conversion functions in a working configuration.
- Separate what the variables describe from what the configuration actually creates.

## The type families in this lab

| Family | Members | Variables here | Rule to remember |
|---|---|---|---|
| Primitive | `string`, `number`, `bool` | `project_name`, `subnet_count`, `enable_dns` | One value. `number` covers integers and decimals; Terraform has no separate `float` or `int`. |
| Collection | `list(T)`, `set(T)`, `map(T)` | `availability_zones`, `allowed_instance_types`, `vpc_cidrs` | Many values of one type. `list` is ordered and indexed; `set` is unique and not indexed; `map` is keyed by strings. |
| Structural | `object({...})`, `tuple([...])` | `app_config`, `database_endpoint`, `ingress_rules` (a list of objects) | Values of different types with a fixed shape. `object` has named attributes; `tuple` has positions. |
| Special | `any`, `null` | `wildcard`, `kms_key_id` | `any` accepts any type; `null` means absence of a value. `optional()` is a modifier inside `object`, not a type. |

Terraform has exactly three primitive types, three collection types, and two structural types. Names such as `float`, `int`, `tree`, `array`, `dict`, and `pair` are not Terraform types; `optional()` is a modifier, not a type. Recognizing those distinctions is part of associate-level objective 4d, complex types.

A literal `[...]` starts life as a tuple, and a literal `{...}` starts life as an object. Terraform converts them to a list or map when the destination declares that type. That is why a plain list of strings can satisfy `list(string)`, and why the distinction still matters when you index or iterate.

### Ordered collections: `list`

`availability_zones` is `list(string)`: order is part of the value, duplicates are allowed, and positions start at zero. `var.availability_zones[0]` is `"us-east-1a"`. `local.primary_az` makes the same read, and `local.azs_joined` uses `join(",", ...)` to produce `"us-east-1a,us-east-1b,us-east-1c"` without losing the order.

The order is a decision, not a detail. `main.tf` assigns `availability_zone = var.availability_zones[count.index]`, so subnet `[0]` gets the first zone, `[1]` the second, and so on. If you reorder the list, the subnets move. If you ask for index `3` with the default three-element list, Terraform reports an invalid index; it does not wrap around.

### Unique collections: `set`

`allowed_instance_types` is `set(string)`: Terraform removes duplicates and does not give the elements positions. Direct indexing fails:

```hcl
> var.allowed_instance_types[0]
# Error: Invalid index
# This value does not have any indices.
```

`tolist(var.allowed_instance_types)` succeeds, but the resulting order is Terraform's set iteration order, not the order you typed. Treat the first element as "one member of the set", never as "the preferred type". If preference matters, keep a separate ordered `list(string)`; a set is for membership and stable keys, not ranking.

The set matters in `main.tf`: `for_each = toset(var.availability_zones)` gives the SSM parameters one instance per zone. A set of strings is one of the two shapes `for_each` accepts (the other is a map), and for a set `each.key` and `each.value` are the same string. A plain list would fail there; that is the reason for the explicit conversion.

### Keyed collections: `map`

`vpc_cidrs` is `map(string)`: every key is a string and every value is a string. Read it with brackets:

```hcl
> var.vpc_cidrs["us-east-1"]
"10.0.0.0/16"
```

`var.vpc_cidrs[0]` fails because `0` is not a key, and `var.vpc_cidrs.us-east-1` fails because the hyphen is not valid in dot notation. Use brackets for map keys, especially when the key contains punctuation or comes from a variable.

`local.cidr_safe` uses `lookup(var.vpc_cidrs, "ap-south-1", "10.99.0.0/16")`. The key is absent, so `lookup` returns the fallback string. If the map later gains an `ap-south-1` entry, that value wins and the fallback disappears. This is different from `var.vpc_cidrs["ap-south-1"]`, which would fail on the missing key.

`keys(var.vpc_cidrs)` returns the three keys in lexical order: `["eu-west-1", "us-east-1", "us-east-2"]`. `length(var.vpc_cidrs)` is `3`. The map has three entries, but only the `us-east-1` value feeds the VPC CIDR; the other two are labels for buckets and tags. That distinction is the single-region trap described below.

### Fixed schemas: `object`

`app_config` is an `object` with one required attribute and four optional ones:

```hcl
type = object({
  name          = string
  instance_type = optional(string, "t3.micro")
  replicas      = optional(number, 2)
  monitoring    = optional(bool, false)
  tags          = optional(map(string), {})
})
```

The schema is fixed: `name` must be present, while the other attributes may be omitted. Terraform fills the omitted ones with their defaults before the configuration reads them. Compared with `map(string)`, an object has fixed attribute names and can mix types; a map has arbitrary string keys and homogeneous values. Use an object for a known configuration shape, and a map for open key-to-value data such as tags. With the defaults in `variables.tf`, the effective value is:

```text
name          = "api"
instance_type = "t3.micro"
replicas      = 2
monitoring    = false
tags          = {}
```

With no overrides, `var.app_config.name` and `var.app_config["name"]` both return `"api"`, and `var.app_config.replicas` returns `2`. The dot form reads an attribute; the bracket form is useful when the attribute name is computed. Omit `name` from a supplied object and validation fails: only attributes marked `optional()` may be omitted.

`app_config.tags` is a valid empty map, but it is not merged into the resources. `local.final_tags` only combines the literal `Project`/`ManagedBy` map with `var.extra_tags`. If you want tags on the VPC, subnets, and buckets, use `extra_tags`; setting `app_config.tags` alone changes a variable and nothing else.

### Fixed positions: `tuple`

`database_endpoint` is `tuple([string, number, bool])`, a three-element value where each position has a different type. `[0]` is the host, `[1]` is the port, and `[2]` is the TLS flag:

```hcl
> var.database_endpoint[0]
"db.internal"
> var.database_endpoint[1]
5432
> var.database_endpoint[2]
true
> local.db_url
"postgres://db.internal:5432"
```

The URL is built by interpolating positions `0` and `1`; the boolean is ignored. It is a string, not a database connection: this lab creates no database. A two- or four-element value fails validation because the tuple's length is fixed. Use a tuple when the positions mean different things; use a list when the elements are interchangeable.

### Nested structures: `list(object(...))`

`ingress_rules` is a list of objects, and each object contains a list of CIDR strings:

```hcl
type = list(object({
  description = string
  port        = number
  protocol    = optional(string, "tcp")
  cidr_blocks = list(string)
}))
```

`local.open_ports` iterates the list and extracts `rule.port`, producing `80` and `443` in the order the rules appear. The optional `protocol` is filled with `"tcp"` even though the default literals omit it. The result is a list-like value of numbers, not a set; duplicate ports would remain duplicates. This value is only used in a local: no security group, ingress rule, or public route is created from it.

### Conversions, `any`, and `null`

The `to*` functions move between families explicitly. `tostring(var.database_endpoint[1])` returns `"5432"`, `tonumber("42")` returns `42`, `tolist(var.allowed_instance_types)` turns the set into a list, and `toset(var.availability_zones)` turns the list into a set. `merge(var.extra_tags, { Extra = "si" })` returns a map containing `Extra`; when both maps share a key, the right-hand map wins. One naming trap: the function is `length()`, not `tolength()`; it works on strings, lists, sets, and maps, while `count` is a meta-argument, not a function.

`wildcard` has no `type` argument, so it is equivalent to `type = any`: it accepts any value. Its default is an object, but that is not a constraint. `any` is a wildcard, not permission for heterogeneous values: `map(any)` still requires all values to share one type; use an `object` when the attributes have different types. `kms_key_id` is a string with `default = null` and `nullable = true`; `null` means "not provided", not `""`. `nullable = false` would reject an explicit `null`; it does not make an omitted variable fail when a default exists. No resource in this lab consumes either variable; they are examples of the `any` and `null` corners of the type system.

## How a local variable file changes values

`terraform.tfvars` is ignored by Git and is not included in a fresh clone. If you create one locally containing the following example, Terraform loads it automatically:

```hcl
app_config = {
  name     = "web"
  replicas = 5
}
```

The effective `app_config` would then be `web`/`5`, not the variable's `api`/`2` defaults. If you add an `*.auto.tfvars` file, it loads after `terraform.tfvars`; a `-var` or `-var-file` on the command line can override both, with later command-line values winning. Check for existing local overrides before creating or changing a variable file.

This particular override does not affect resource counts: `app_config` feeds only the `app_*` locals, and no resource reads those locals. Console values do change, however. Other overrides can change the plan.

## Prerequisites

Use Terraform 1.12.0 or newer, registry access to download the AWS provider (`~> 5.0`), and AWS credentials with permission to read the caller identity and manage VPCs, subnets, S3 buckets, and SSM parameters. The provider is fixed to `us-east-1`; the configuration does not deploy to the other regions named in the map.

`terraform plan` reads `data.aws_caller_identity.current`, so it contacts AWS even though it creates nothing. `terraform apply` creates real resources. Use a sandbox account, review the plan, and choose a unique `project_name` if the account is shared: the S3 bucket names and SSM parameter names are derived from it.

The configuration does not define EC2 instances, a database, a security-group rule, a NAT gateway, or a KMS key. Variables such as `allowed_instance_types`, `database_endpoint`, `ingress_rules`, and `kms_key_id` are type exercises, not descriptions of deployed infrastructure. AWS creates the VPC's default route table and default security group automatically, but the lab does not add routes or rules to them. The default Availability Zone names assume `us-east-1a`, `us-east-1b`, and `us-east-1c` exist in your account; adjust the list if your account exposes different names.

## Explore the expressions

From this directory:

```sh
terraform init
terraform fmt -check
terraform validate
terraform console
```

`fmt -check` reports formatting differences without rewriting files; run `terraform fmt` if you want to apply them. `validate` needs `init` first because it loads the provider schema. The console loads the configuration and the tfvars file, so the values below are the effective values, not the raw defaults.

The expressions in this guide read variables and locals. They do not create resources; evaluating a data source in the console is a separate action that can call AWS.

### Quick reference

| Expression | Expected result | Why |
|---|---|---|
| `var.availability_zones[0]` | `"us-east-1a"` | `list` is ordered and zero-indexed. |
| `local.cidr_safe` | `"10.99.0.0/16"` | `lookup` returns the fallback for the absent `ap-south-1` key. |
| `local.open_ports` | `80` and `443` | The `for` expression extracts `port` from each object in list order. |
| `local.db_url` | `"postgres://db.internal:5432"` | Tuple positions `0` and `1` are interpolated. |
| `var.app_config.name` | `"api"` | The variable default supplies the required name. |
| `var.app_config.replicas` | `2` | The optional attribute default applies. |
| `var.app_config.instance_type` | `"t3.micro"` | The optional default fills the omitted attribute. |
| `var.database_endpoint[1]` | `5432` | Tuple position `1` is the port and keeps its number type. |
| `type(var.database_endpoint)` | A three-element tuple of `string`, `number`, `bool` | `type` reports the inferred type; a tuple keeps a different type per position. |
| `var.allowed_instance_types[0]` | Error: invalid index | A `set` has no positions. |
| `tolist(var.allowed_instance_types)[0]` | One of the three types | The conversion works, but the first element is not a declared preference. |
| `var.vpc_cidrs[0]` | Error: invalid index | The map has no `"0"` key; map indices are keys, not positions. |
| `var.vpc_cidrs["us-east-1"]` | `"10.0.0.0/16"` | The map key is a string. |
| `length(var.vpc_cidrs)` | `3` | The map has three entries. |
| `keys(var.vpc_cidrs)` | `["eu-west-1", "us-east-1", "us-east-2"]` | `keys` returns the keys in lexical order. |
| `merge(var.extra_tags, { Extra = "si" })` | `{ Extra = "si" }` | `extra_tags` is empty; the right-hand map wins on conflicts. |
| `var.kms_key_id` | `null` | The default is absence of a value, not an empty string. |
| `var.wildcard` | `{ cualquier = "cosa" }` | No `type` means `any`; the default is accepted as-is. |

The table is a checklist, not a substitute for the reasoning; the sections above explain the access rules, and one conversion trap is worth calling out separately.

### A conversion that can surprise you

`map(string)` accepts primitive conversions. If you set `vpc_cidrs` to `{ "us-east-1" = "10.0.0.0/16", "us-east-2" = 42 }`, Terraform can convert `42` to `"42"` and accept the map. The type constraint is satisfied, but `"42"` is not a CIDR. In this lab the `us-east-2` value is only a tag and a bucket-name suffix, so the mistake would not fail at apply; it would simply be wrong data. Types catch shape, not meaning; add validation when the content matters.

## What a plan actually creates

The plan depends on your own state and account. An empty state does not guarantee that matching AWS resources are absent: a fresh apply can collide with existing bucket or parameter names. State backups are not read during normal planning and must be kept private; never delete state to simulate a clean start.

With the empty primary state and the checked-in tfvars, a plan proposes ten managed resources:

| Resource | Instances | Addresses | Notes |
|---|---|---|---|
| `aws_vpc.main` | 1 | `aws_vpc.main` | CIDR from `vpc_cidrs["us-east-1"]`; DNS hostnames from `enable_dns`. |
| `aws_subnet.by_count` | 3 | `aws_subnet.by_count[0]` … `[2]` | `/24` subnets inside `10.0.0.0/16`; AZ selected by list index. |
| `aws_s3_bucket.by_region` | 3 | `aws_s3_bucket.by_region["us-east-1"]` … | One per map key; all created in `us-east-1`. |
| `aws_ssm_parameter.az_marker` | 3 | `aws_ssm_parameter.az_marker["us-east-1a"]` … | One per zone; `String` parameters; `each.key == each.value`. |

The data source is read during the plan but is not a managed resource. The plan does not create anything; `apply` does.

Only six variables reach resources: `project_name` (bucket prefix and SSM names), `subnet_count` (count), `enable_dns` (VPC DNS hostnames), `availability_zones` (subnet zones and SSM keys), `vpc_cidrs` (VPC CIDR and bucket keys/tags), and `extra_tags` (merged tags). The remaining variables are console and type exercises.

### The single-region trap

`providers.tf` fixes the provider to `us-east-1`. The keys of `vpc_cidrs` are labels, not provider regions. Only the `"us-east-1"` value is used as the VPC CIDR; the `"us-east-2"` and `"eu-west-1"` values become tags and bucket-name suffixes. All three buckets are created in `us-east-1`, even though their names contain other region names.

That is deliberate: the map gives `for_each` three stable keys and demonstrates keyed resources. It is not a multi-region deployment. To create resources in other regions you would need provider aliases or separate configurations, which this lab does not include. The default Availability Zones are also `us-east-1a`, `us-east-1b`, and `us-east-1c`; changing the provider region without changing that list would produce invalid subnet zones.

### Bounds and preconditions

`subnet_count` is a `number`, but `count` requires a whole number. `3` is fine; `2.5` is not. With the default three zones, `subnet_count` must be a whole number from `0` to `3` inclusive: a larger value makes `var.availability_zones[count.index]` fail with an invalid index. A smaller value creates fewer subnets, while the three SSM parameters and three buckets remain, because those loops are driven by `availability_zones` and `vpc_cidrs`, not by `subnet_count`.

`cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)` adds eight bits to the VPC prefix. With `10.0.0.0/16`, the subnets are `10.0.0.0/24`, `10.0.1.0/24`, and `10.0.2.0/24`. If you replace the VPC CIDR with a block too small for eight extra bits, the expression fails. The default is sized for this example.

### Names and collisions

The bucket name is `${lower(var.project_name)}-${each.key}-${data.aws_caller_identity.current.account_id}`. With the default project name, the three names look like `tf-assoc-l7-us-east-1-<account-id>`, `tf-assoc-l7-us-east-2-<account-id>`, and `tf-assoc-l7-eu-west-1-<account-id>`. S3 bucket names are globally unique, so an existing name in any account blocks the apply. The account ID reduces the chance of a collision but does not eliminate it. Lowercasing helps with uppercase project names, but it does not remove underscores or other characters that S3 rejects; choose a project name that is already a valid bucket prefix.

The SSM parameter names are `/${var.project_name}/az/<zone>`. They are scoped to the account and region, not globally unique. In a shared account, a different lab using the same `project_name` would target the same parameter names. The create can fail because the parameter already exists; if the resource is already in this state, `destroy` will delete it. Use a unique prefix, and do not reuse a prefix that belongs to another team.

### What is not created

`allowed_instance_types` does not create EC2 instances; it only feeds `local.first_type` and `local.types_count`. `database_endpoint` does not create a database; it only feeds the `db_*` locals and the URL string. `ingress_rules` does not create a security group or open ports; it only feeds `local.open_ports`. `kms_key_id` is declared but not referenced by any resource. `wildcard` is declared but not referenced. `app_config.tags` is not merged into resource tags; only `extra_tags` is.

There is no `outputs.tf` in this directory. `terraform output` therefore has nothing to print, even after an apply. Use `terraform state list` to inspect the addresses, and `terraform state show <address>` if you need the attributes of one resource.

The configuration does not create an internet gateway, NAT gateway, or custom route table, and it does not add a route to the internet. AWS creates a default route table and default security group with the VPC; they remain at their defaults. The subnets are not made public by the lab. `enable_dns` sets `enable_dns_hostnames` on the VPC; it does not add connectivity.

## Costs

The configuration creates no EC2 instances, NAT gateway, RDS database, or KMS key. It does create S3 buckets and SSM parameters, and AWS requests or any data you add may incur charges. Check current pricing and account settings rather than assuming a zero-cost run.

The estimate changes if you upload objects, enable versioning, or leave resources running. It also depends on your account and region; check current AWS pricing for your account. `terraform console`, `fmt`, and `validate` do not create resources. `terraform plan` reads the caller identity and contacts AWS, but it creates nothing and does not charge for the resources in the plan.

## Apply, inspect, and clean up

Review the plan before applying. With the empty primary state and the checked-in tfvars, `terraform apply` should propose the ten additions above; approve only if the plan matches your account and intended names.

```sh
terraform plan
terraform apply
terraform state list
```

After an apply, `terraform state list` should show the VPC, the three indexed subnets, the three keyed buckets, and the three keyed SSM parameters. The difference between `aws_subnet.by_count[0]` and `aws_s3_bucket.by_region["us-east-1"]` is the difference between `count` (numeric positions) and `for_each` (stable keys). If you change the map keys later, the keyed addresses change; if you reorder the list, the indexed addresses keep their numbers but point at different zones.

When you are finished, destroy with the same variable values you applied with:

```sh
terraform destroy
```

Review the destruction plan and approve it. Empty the buckets before destroying them; the configuration does not set `force_destroy`, so a non-empty bucket makes the destroy fail. If you enabled versioning or added object versions, delete the versions as well, not only the current objects. Terraform deletes the SSM parameters it created; verify removal in AWS, especially if the account is shared and the names could have existed before.

If you changed `project_name`, `vpc_cidrs`, or `subnet_count` between apply and destroy, switch back to the applied values first so the plan describes the same resources you created. Do not delete resources manually in the AWS console before running `destroy`; that leaves the state stale and makes the next plan misleading. Keep `terraform.tfstate`, `terraform.tfstate.backup`, saved plans, and any local variable files private: state can contain account IDs, resource IDs, and bucket names.

## Verification note

The expected values, resource counts, and error descriptions in this guide come from static inspection of the configuration in this directory. The commands and the AWS deployment were not executed for this README. Console formatting and exact error wording can vary by Terraform and provider version; the configuration requires Terraform 1.12.0 or newer and AWS provider 5.x, and the values described here follow from those files.
