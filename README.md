# Terraform Associate Labs

Hands-on Terraform configurations for exploring infrastructure as code, from provider initialization to AWS networking, expressions, and input validation. Each lab is an independent root module: run Terraform from that lab's directory and keep its state separate.

The exercises connect the concepts behind Terraform to things you can observe: the difference between a version constraint and a dependency lock, a plan and an apply, a resource and a data source, or a variable and a derived local. Each lab explains what the configuration actually contains, suggests checks and experiments, and describes why the result matters. The labs follow the course's progression, but the guides are self-contained for this repository.

## The learning path

Start by initializing a configuration without any infrastructure in **Lab 0**. In **Lab 2**, add providers and see how an alias selects a second AWS region. **Lab 3** makes the plan–apply–state cycle tangible with S3 buckets and an indexed resource. **Lab 5** brings those ideas together in a small AWS network and instance: resource references create a dependency graph, while data sources supply existing account and AMI information.

Week 2 looks inside the language. **Lab 6** follows values through Terraform's main block types. **Lab 7** compares lists, sets, maps, objects and tuples and uses collections to drive resource instances. **Lab 8** turns the configuration into an input contract, testing validation, precedence, derived settings and sensitive outputs. These examples intentionally leave room for exploration; they are not hardened infrastructure templates.

### What a lab offers

1. An explanation of the problem and the relevant Terraform concepts.
2. A map from those concepts to the actual files and resources in the directory.
3. Commands or console experiments, expected observations, and an explanation of what those observations mean.
4. AWS prerequisites, security and cost cautions, and cleanup instructions where resources are created.

The original course sometimes uses a simpler or different example; where that matters, the lab guide distinguishes it from the code shipped here. Output depends on your state, credentials, AWS account, and selected provider versions, so treat examples as expectations rather than transcripts of your run.

> **Learning environment only.** Most labs can create real AWS resources and incur charges. Review every plan, use an isolated account with appropriate permissions, and destroy resources when you finish. These examples are not production-ready security baselines.

## Explore the labs

| Week | Lab | What you will explore |
| --- | --- | --- |
| 01 | [Lab 0 — Initialization](w01/lab0-init/) | Terraform and provider requirements, initialization, and the lock file |
| 01 | [Lab 2 — Providers](w01/lab2-providers/) | Default and aliased AWS providers across two regions |
| 01 | [Lab 3 — Workflow](w01/lab3-workflow/) | Plan, apply, state, `count`, and cleanup |
| 01 | [Lab 5 — First project](w01/lab5-first-project/) | A VPC, EC2 instance, IAM, data sources, and an S3 bucket |
| 02 | [Lab 6 — Configuration blocks](w02/lab6-bloques/) | Variables, locals, data sources, resources, and outputs |
| 02 | [Lab 7 — Types and expressions](w02/lab7-types/) | Collections, objects, conversions, `count`, and `for_each` |
| 02 | [Lab 8 — Variables](w02/lab8-variables/) | Validation, sensitive values, and environment-dependent configuration |

The numbering follows the course; only directories currently present in this repository are listed.

## Before you start

- Install Terraform **1.12.0** to satisfy every lab, including Lab 3's exact version constraint. Other labs permit newer versions, subject to their provider constraints.
- Allow provider downloads during `terraform init`. The committed `.terraform.lock.hcl` files record provider selections and checksums; review changes to them.
- For AWS labs, configure credentials outside the repository and use an account with permissions for the resources and data sources in the chosen lab. Check the target account and region before planning or applying.
- Bucket names are globally scoped within an AWS partition and can collide. Resource names, regional availability, quotas, IAM permissions, and existing state can also affect results.

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

## State, secrets, and publishing

Terraform state and saved plans can contain sensitive values, even when an output is marked `sensitive`. This repository's `.gitignore` excludes state, `.terraform/`, variable files, and a file named `tfplan`; it does **not** exclude every possible saved-plan filename. Do not commit credentials, state, state backups, private variable files, or saved plans. An ignore rule does not remove files already tracked or previously committed, so inspect both the files to be published and Git history before making the repository public.

## Verification

The lab guides describe expected observations based on static inspection of the configurations. The commands and AWS deployments were not executed as part of writing these guides; provider behavior, permissions, costs, and results must be checked in your own environment.
