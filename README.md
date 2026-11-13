# Terraform Associate Labs

![Terraform](https://img.shields.io/badge/Terraform-1.12%2B-7B42BC?logo=terraform&logoColor=white)
![AWS provider](https://img.shields.io/badge/AWS%20provider-5.x-FF9900)
![Study track](https://img.shields.io/badge/study%20track-Terraform%20Associate%20%28004%29-7B42BC)
![Labs](https://img.shields.io/badge/labs-11-2F855A)

Hands-on Terraform configurations for exploring infrastructure as code, from provider initialization to AWS networking, expressions, input validation, dynamic collections, and lifecycle rules. Each lab is an independent root module: run Terraform from that lab's directory and keep its state separate.

The exercises connect the concepts behind Terraform to things you can observe: the difference between a version constraint and a dependency lock, a plan and an apply, a resource and a data source, or a variable and a derived local. Each lab explains what the configuration actually contains, suggests checks and experiments, and describes why the result matters. The labs follow the course's progression, but the guides are self-contained for this repository.

## Portfolio snapshot

This repository is my hands-on Terraform notebook for the HashiCorp Certified: Terraform Associate (004) exam. Each lab turns a lesson topic into something observable: a provider lock, a plan, a state address, a rendered template, a replacement order. The guides are written so that another engineer can clone the repository, follow the same steps, and compare the result with the expected behavior.

The current focus is **Lab 11 — lifecycle meta-arguments and explicit dependencies**.

## Skills demonstrated

| Area | Where it shows up |
| --- | --- |
| Terraform workflow | `init`, `fmt`, `validate`, `plan`, `apply`, `destroy`, state inspection |
| Providers and versions | Version constraints, dependency lock file, provider aliases, two regions |
| AWS foundations | VPC, subnets, internet gateway, route tables, security groups, EC2, S3, IAM |
| HCL and inputs | Blocks, types, variables, locals, outputs, validation, sensitive values |
| Functions and templates | CIDR math, `file`, `templatefile`, `fileset`, `filemd5` |
| Dynamic infrastructure | `count`, `for_each`, `dynamic` blocks, splat, map comprehensions |
| Lifecycle and dependencies | `prevent_destroy`, `create_before_destroy`, `ignore_changes`, `replace_triggered_by`, `depends_on` |

## Repository layout

```text
.
├── README.md
├── w01/
│   ├── lab0-init/
│   ├── lab1-iac-concepts/      # reading note, no configuration
│   ├── lab2-providers/
│   ├── lab3-workflow/
│   └── lab5-first-project/
└── w02/
    ├── lab6-bloques/
    ├── lab7-types/
    ├── lab8-variables/
    ├── lab9-functions/
    ├── lab10-dinamico/
    └── lab11-lifecycle/
```

## The learning path

Start by initializing a configuration without any infrastructure in **Lab 0**. **Lab 1** is a one-page reading note on the declarative model, the state file, and the plan; it has no configuration to run. **Lab 2** adds providers and shows how an alias selects a second AWS region. **Lab 3** makes the plan–apply–state cycle tangible with S3 buckets and an indexed resource. **Lab 5** brings those ideas together in a small AWS network and instance: resource references create a dependency graph, while data sources supply existing account and AMI information.

Week 2 looks inside the language. **Lab 6** follows values through Terraform's main block types. **Lab 7** compares lists, sets, maps, objects, and tuples and uses collections to drive resource instances. **Lab 8** turns the configuration into an input contract, testing validation, precedence, derived settings, and sensitive outputs. **Lab 9** moves from syntax to computation: CIDR math, `templatefile`, `fileset`, and `filemd5` build a VPC, an nginx instance, and a small S3 site. **Lab 10** replaces positional `count` with stable `for_each` keys, generates nested security group blocks with `dynamic`, and turns a resource map into a list with a splat expression. **Lab 11** is a practice skeleton for lifecycle rules: `prevent_destroy`, `create_before_destroy`, `ignore_changes`, `replace_triggered_by`, and the difference between implicit references and explicit `depends_on`.

These examples intentionally leave room for exploration; they are not hardened infrastructure templates.

### What a lab offers

1. An explanation of the problem and the relevant Terraform concepts.
2. A map from those concepts to the actual files and resources in the directory.
3. Commands or console experiments, expected observations, and an explanation of what those observations mean.
4. AWS prerequisites, security and cost cautions, and cleanup instructions where resources are created.
5. For Lab 11, a clear statement of which lifecycle blocks you must write yourself; the guide describes the expected behavior rather than handing over the solution.

The original course sometimes uses a simpler or different example; where that matters, the lab guide distinguishes it from the code shipped here. Output depends on your state, credentials, AWS account, and selected provider versions, so treat examples as expectations rather than transcripts of your run.

> **Learning environment only.** Most labs can create real AWS resources and incur charges. Review every plan, use an isolated account with appropriate permissions, and destroy resources when you finish. These examples are not production-ready security baselines.

## Explore the labs

| Week | Lab | What you will explore | Format |
| --- | --- | --- | --- |
| 01 | [Lab 0 — Initialization](w01/lab0-init/) | Terraform and provider requirements, initialization, and the lock file | Local |
| 01 | [Lab 1 — IaC concepts](w01/lab1-iac-concepts/) | Declarative model, state, plan, idempotence, and drift | Reading |
| 01 | [Lab 2 — Providers](w01/lab2-providers/) | Default and aliased AWS providers across two regions | AWS |
| 01 | [Lab 3 — Workflow](w01/lab3-workflow/) | Plan, apply, state, `count`, and cleanup | AWS |
| 01 | [Lab 5 — First project](w01/lab5-first-project/) | A VPC, EC2 instance, IAM, data sources, and an S3 bucket | AWS |
| 02 | [Lab 6 — Configuration blocks](w02/lab6-bloques/) | Variables, locals, data sources, resources, and outputs | AWS |
| 02 | [Lab 7 — Types and expressions](w02/lab7-types/) | Collections, objects, conversions, `count`, and `for_each` | AWS |
| 02 | [Lab 8 — Variables](w02/lab8-variables/) | Validation, sensitive values, and environment-dependent configuration | AWS |
| 02 | [Lab 9 — Functions and templates](w02/lab9-functions/) | CIDR math, `templatefile`, `fileset`, `filemd5`, and S3 objects | AWS |
| 02 | [Lab 10 — Dynamic expressions](w02/lab10-dinamico/) | `for_each`, `dynamic` blocks, splat, and map comprehensions | AWS |
| 02 | [Lab 11 — Lifecycle](w02/lab11-lifecycle/) | `prevent_destroy`, `create_before_destroy`, `ignore_changes`, `replace_triggered_by`, and implicit vs explicit dependencies | AWS exercise |

The numbering follows the course; missing numbers are lessons without a lab in this repository. Lab 1 is a reading note; the rest are runnable root modules.

## Before you start

- Install Terraform **1.12.0** to satisfy every lab, including Lab 3's exact version constraint. Other labs permit newer versions, subject to their provider constraints.
- Allow provider downloads during `terraform init`. The committed `.terraform.lock.hcl` files record provider selections and checksums; review changes to them.
- For AWS labs, configure credentials outside the repository and use an account with permissions for the resources and data sources in the chosen lab. Check the target account and region before planning or applying.
- Bucket names are globally scoped within an AWS partition and can collide. Resource names, regional availability, quotas, IAM permissions, and existing state can also affect results.
- Read Lab 11 before running it: the lifecycle blocks are intentionally left as an exercise, and `prevent_destroy` will block cleanup until you remove it.

## Typical workflow

From the repository root, choose a lab and follow its README. For example:

```sh
cd w01/lab2-providers
terraform init
terraform fmt -check
terraform validate
terraform plan
```

`init` downloads providers; `fmt -check` checks formatting without changing files; `validate` checks the configuration; and `plan` previews changes against the current state and AWS. A plan can contact AWS and may need credentials even though it does not apply the proposed changes. `terraform apply` and `terraform destroy` make real changes: use them only after reviewing the lab instructions and the proposed actions.

Useful follow-up commands once a lab is applied:

```sh
terraform output
terraform state list
terraform destroy
```

## State, secrets, and publishing

Terraform state and saved plans can contain sensitive values, even when an output is marked `sensitive`. This repository's `.gitignore` excludes state, `.terraform/`, variable files, and a file named `tfplan`; it does **not** exclude every possible saved-plan filename. Do not commit credentials, state, state backups, private variable files, or saved plans. An ignore rule does not remove files already tracked or previously committed, so inspect both the files to be published and Git history before making the repository public.

Labs 9, 10, and 11 can create local state and backup files in their directories. They are ignored by Git, but they still exist on disk. Before publishing, check:

```sh
git ls-files
git status --ignored --short
```

The lock file is safe to commit: it contains provider versions and hashes, not credentials. The state file is not safe to publish: it can contain sensitive attribute values.

## Verification

The lab guides describe expected observations based on static inspection of the configurations and official Terraform documentation. `terraform fmt -check` and `terraform validate` were run for Labs 9 and 10; Lab 11 was initialized, format-checked, and passed a one-off syntax validation, but its lifecycle blocks remain an exercise. No AWS deployment was executed while writing the guides. Provider behavior, permissions, costs, and results must be checked in your own environment.
