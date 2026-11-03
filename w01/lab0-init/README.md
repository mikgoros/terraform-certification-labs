# Lab 0 — Initialize a Terraform configuration

A Terraform configuration is more than a text file with resource blocks. Before Terraform can plan anything, it must know which Terraform Core versions are acceptable, which provider plugins the configuration needs, which exact provider versions to use, and where those plugins live on disk. Lab 0 isolates that preparation step. There are no resources, so there is no infrastructure to create, no state to protect, and no AWS bill to worry about. The whole lab is about making a working directory reproducible.

This directory is the hands-on companion to the setup lesson `lessons/00-setup-entorno.md`. The lesson covers the full environment: Terraform installation, AWS credentials, repository conventions, auxiliary tools, and HCP Terraform. This lab exercises only the `terraform init` slice. It is small on purpose: when `init` fails later in a real project, the cause is usually one of the things you can see here — a version guard, a provider constraint, a lock file, or a stale cache.

One detail matters before you start: the actual `main.tf` is not identical to the optional version-only challenge at the end of Lesson 0. It also declares the AWS provider. That difference is deliberate and is the main teaching point of this lab.

## What this lab teaches

- Read `required_version` as a Core guard, not an installer.
- Read `required_providers` as a dependency declaration, not a provider configuration.
- Explain how `terraform init` turns a constraint into a selected provider and a lock entry.
- Distinguish the lock file from the cache and from state.
- Decide what belongs in Git and what must stay local.
- Run the local-only commands without AWS credentials.

## Scope: Lesson 0 versus this directory

Lesson 0 is broader than this lab. It teaches the whole setup, including credentials, tooling, and HCP Terraform. This README does not replace it and does not compress it. The course contract requires the lesson to be studied section by section; the lab is where you execute and observe the part that concerns initialization. The table below records the differences so you do not mistake one artifact for the other.

| Topic | Lesson 0 | This directory |
|---|---|---|
| Core version | §1 and Step 6 use `required_version = ">= 1.12.0"` | Same guard |
| Provider requirement | Step 6's minimal `main.tf` has no `required_providers` | `main.tf` declares `hashicorp/aws ~> 5.0` |
| Lock file | The version-only case is described as producing a lock file with no provider entries | `.terraform.lock.hcl` contains AWS 5.100.0 |
| `init` result | Creates `.terraform/` and `.terraform.lock.hcl` | Same, plus installs the AWS provider |
| `validate` | Expects success | Same |
| `plan` | Expects “No changes” | Same; no resources |
| AWS credentials | §2 explains environment variables for later labs | Not needed here |
| Auxiliary tools | §4 installs `tflint`, `terraform-docs`, `pre-commit` | Not required here |
| HCP Terraform | §5 creates an account and token for M6 | Not used here |
| Example version | §3 uses 5.50.0 illustratively | The lock records 5.100.0 |

The lesson is not wrong about the lock file; it is describing a different configuration. A version-only configuration has no provider to lock. Once `required_providers` names AWS, the lock file has real work to do. The same applies to the version number: 5.50.0 in the lesson is an example of an exact selection, while 5.100.0 is the selection this snapshot actually recorded. Compare roles, not numbers.

## The files in front of you

| Path | Role | Commit? |
|---|---|---|
| `main.tf` | Configuration: Core guard and provider requirement | Yes |
| `.terraform.lock.hcl` | Exact provider selection and package hashes | Yes |
| `.terraform/` | Local provider cache; platform-specific | No |
| `README.md` | This guide | Yes |
| `terraform.tfstate` | Not present; state would record managed objects | No, if it appears |

The working copy contains this cache:

```text
lab0-init/
├── main.tf
├── .terraform.lock.hcl
├── .terraform/
│   └── providers/
│       └── registry.terraform.io/
│           └── hashicorp/
│               └── aws/
│                   └── 5.100.0/
│                       └── darwin_arm64/
└── README.md
```

The `darwin_arm64` directory is a direct observation from this working copy: it was initialized on an Apple Silicon Mac. A Linux machine would have a different platform directory. That is exactly why the cache is not committed. A fresh clone has `main.tf`, the lock file, and this README; it does not have `.terraform/`.

Several things are intentionally absent:

- No `provider "aws"` block. A requirement is not the same as a configured provider.
- No `resource` or `data` blocks. There is nothing to plan.
- No variables, locals, or outputs. There is nothing to parameterize or expose.
- No `backend` block. Terraform would use the local backend; there is no remote state or remote locking.
- No modules. `init` has no module installations to perform.
- No state file. Nothing has been applied.

The absence is the lesson. Each missing piece would add a concern that distracts from what `init` is doing.

## Reading main.tf

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

The `terraform` block is a settings block. It does not create anything.

`required_version` is a guard on Terraform Core. It says that this configuration expects at least 1.12.0. Terraform checks it when a command loads the configuration; if the running binary is older, the command stops with an unsupported-version error. It does not download or install Terraform. That is the job of your package manager, `tfenv`, or another installer. Because the operator is `>=`, a newer Core such as 1.13 would also pass. For exam alignment, use 1.12.x; the guard is a floor, not a pin.

`required_providers` is a dependency declaration. The key `aws` is the local name used in this configuration. `source = "hashicorp/aws"` is shorthand for `registry.terraform.io/hashicorp/aws`; the lock file writes the full address. `version = "~> 5.0"` is a pessimistic constraint: it accepts 5.0.0 and later 5.x releases, but not 6.0.0. It is not the same as “5.0 exactly”. A constraint of `~> 5.0.0` would be narrower, allowing only 5.0.x.

There is no `provider "aws"` block. That is not an oversight. A provider block configures a provider — region, credentials, default tags, assume-role settings. This configuration has no resources that need AWS, so it declares the dependency to exercise installation and locking but does not configure a client. If you added an `aws_s3_bucket`, the provider would need a region and credentials; the lab would cross from local setup into cloud work.

Finally, there are no resources. A plan in this directory has nothing to compare and nothing to propose. That is why the expected plan is “No changes”. It is not a sign that `init` failed.

## What terraform init actually does

`terraform init` turns the declarations in `main.tf` into a prepared working directory. It is safe to run repeatedly; it does not create infrastructure. Conceptually it does four things.

1. **Initializes the backend.** With no `backend` block, Terraform uses the local backend. There is no remote state and no remote locking. If resources existed, state would live locally by default.
2. **Reads provider requirements.** It resolves `hashicorp/aws` to the registry address and reads the `~> 5.0` constraint.
3. **Selects and installs.** If `.terraform.lock.hcl` has a compatible entry, it uses that exact version — 5.100.0 in this snapshot. If the cache already contains it, it reuses it; otherwise it downloads and verifies it. Without a lock, it would select the newest version that satisfies the constraint and write a new lock entry.
4. **Writes or updates the lock file.** It records the selected version, the constraint, and hashes. It may add hashes for the current platform. It does not install Terraform Core.

Modules are not part of this lab; there are none to install. The result is a prepared directory, not a deployed environment.

Representative output on a clean cache:

```text
Initializing the backend...

Initializing provider plugins...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)

Terraform has been successfully initialized!
```

If the cache is already populated, the middle lines may say `Using previously-installed hashicorp/aws v5.100.0` instead. If the lock file is already present, the “created a lock file” message may be absent. Exact wording varies by Terraform version and by whether `init` had work to do.

A useful mental model: `required_providers` is the shopping list, the lock file is the receipt with the exact item and serial numbers, `.terraform/` is the box where the item is unpacked, and `init` is the shopper. The analogy stops at the cloud boundary: the shopper never calls AWS.

## The lock file is not state

The actual lock file records this selection (the hash list is abridged here):

```hcl
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.100.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:...",
    "zh:...",
  ]
}
```

The lock file is small, human-readable, and meant to be committed. It answers a narrower question than state: which exact provider package did this configuration select, and which hashes prove the package is the one that was selected? The `version` field is exact. The `constraints` field mirrors the range that produced the selection. The `h1:` hash is a content hash of the provider package; the `zh:` hashes are archive hashes for platform packages. Terraform uses them to verify downloads.

The full provider address is `registry.terraform.io/hashicorp/aws`, even though `main.tf` writes the shorthand `hashicorp/aws`. The lock file normalizes the address.

It is not state. State records the objects Terraform manages: IDs, attributes, dependency metadata. This lab has no such objects. If you later add a resource and apply, a `terraform.tfstate` would appear; that file is a different artifact with different handling. The lock file does not pin Terraform Core either — `required_version` is the only Core constraint — and it does not lock modules, whose versions come from their source declarations.

| Artifact | Question it answers | Changes when | Commit? |
|---|---|---|---|
| `required_version` | Can this Core run the configuration? | You edit the guard | Yes, in `main.tf` |
| `required_providers` | Which provider range is acceptable? | You edit the requirement | Yes, in `main.tf` |
| `.terraform.lock.hcl` | Which exact provider version and hashes? | `init` resolves a new selection; platform hashes are added | Yes |
| `.terraform/` | Where are the downloaded binaries? | `init` downloads, or you delete the cache | No |
| `terraform.tfstate` | What objects exist? | `apply`, `destroy`, `refresh` | No |

This table is the core distinction the lab is trying to make. The constraint is a range; the lock is a selection; the cache is a copy; the state is a record of real objects. Mixing them up leads to the wrong Git decisions and the wrong debugging instincts.

Commit the lock because it makes the selection reproducible across machines and CI and lets Terraform verify package integrity. Do not hand-edit it; Terraform maintains it. `terraform init -upgrade` is the deliberate way to re-resolve providers within the constraint; review the diff afterward. If you delete the lock, `init` may select a newer 5.x version, which is exactly the drift the lock prevents.

## Practice

These experiments are local. They do not create AWS resources. Run them from this directory. If you are studying with a tutor, show the actual output rather than only saying that it worked.

### Experiment 1 — Establish the baseline

**Objective:** Confirm that the directory is initialized and that formatting, validation, provider listing, and planning behave as expected.

**Steps:**

1. Check the Terraform binary.
2. Initialize the directory.
3. Run the read-only checks in order.

```sh
terraform version
terraform init
terraform fmt -check
terraform validate
terraform providers
terraform plan
```

**Expected result:**

- `terraform version` reports `Terraform v1.12.x` or newer. If it is older than 1.12.0, stop and install 1.12.x; the guard will reject the configuration.
- `init` finishes with `Terraform has been successfully initialized!` and reports AWS 5.100.0 as installed or previously installed.
- `fmt -check` produces no output and exits successfully. That means the files already match canonical formatting.
- `validate` reports `Success! The configuration is valid.`
- `providers` lists `provider[registry.terraform.io/hashicorp/aws]` with the `~> 5.0` requirement. Tree characters and formatting can vary.
- `plan` reports `No changes. Your infrastructure matches the configuration.` There are no resources to create.

**Solution:** The solution is the command sequence itself, run from this directory. If all six results match, the baseline is correct. If `validate` complains that a provider is missing, run `terraform init` first. If `plan` proposes resources, you are in the wrong directory or a state file is present.

**Criteria:** You can explain what each command proves and what it does not prove. In particular, `init` success is a dependency-setup result, not an AWS permission test.

### Experiment 2 — Show that the cache is disposable and the lock is authoritative

**Objective:** Prove that `.terraform/` is a cache, not the source of truth.

**Steps:**

1. Read the locked provider version.
2. Remove only the local cache.
3. Re-run `init`.
4. Read the locked version again.

```sh
grep 'version' .terraform.lock.hcl
rm -rf .terraform
terraform init
grep 'version' .terraform.lock.hcl
```

**Expected result:** The second `init` recreates `.terraform/` and installs the same 5.100.0 selection. The lock file still records 5.100.0; it may be unchanged or gain hashes for the current platform. Removing the provider cache does not remove state.

**Solution:** If `init` installs 5.100.0 again instead of a newer 5.x release, the lock did its job. If `init` fails while offline, the cache was needed for that run; restore network access or accept that a clean initialization normally queries the registry. Do not delete the lock to “fix” the cache.

**Criteria:** You can explain why deleting `.terraform/` is safe while deleting `.terraform.lock.hcl` changes the reproducibility guarantee.

### Experiment 3 — See a lock/constraint mismatch in a scratch copy

**Objective:** Observe that the lock is a selection, not a suggestion, without changing the real lab.

**Steps:**

1. Create a temporary directory and copy the configuration and lock file into it.
2. Change the constraint to a version that the locked provider cannot satisfy.
3. Run `init` and read the error.
4. Delete the scratch directory when finished.

```sh
(
  scratch="$(mktemp -d)"
  cp main.tf .terraform.lock.hcl "$scratch/"
  cd "$scratch"
  sed -i.bak 's/~> 5.0/= 4.0.0/' main.tf
  terraform init
)
```

**Expected result:** `init` fails because the locked version is incompatible with the new constraint (wording may vary). Terraform should not silently downgrade to a 4.x provider.

**Solution:** The error is the correct result: 5.100.0 does not satisfy `= 4.0.0`. To accept a new selection, run `terraform init -upgrade` in the scratch copy; it would resolve 4.0.0 and rewrite the lock. In the real lab, restore the original constraint; do not downgrade just to make the error disappear.

**Criteria:** You can explain why the lock file is checked against the configuration before a new provider is downloaded.

### Experiment 4 — Check Git hygiene

**Objective:** Confirm which files belong in version control.

**Steps:**

1. If this directory is inside a Git repository, inspect the status.
2. Ask Git which rule ignores the cache.

```sh
git status --short
git check-ignore -v .terraform/
```

**Expected result:** `git check-ignore` reports that `.terraform/` is matched by a rule in `labs/.gitignore`. The lock file is not ignored. If it is not tracked yet, it may appear as `?? .terraform.lock.hcl` in `git status`.

**Solution:** Stage `main.tf`, `.terraform.lock.hcl`, and `README.md`; leave `.terraform/` out. If a state or plan file appears, do not stage it. The exact status output depends on which files are already tracked.

**Criteria:** You can state the commit rule without looking at the table: code and lock file yes; cache, state, and plan files no.

## Expected results at a glance

| Command | What success looks like | What it proves |
|---|---|---|
| `terraform version` | `Terraform v1.12.x` or newer | Core is installed and should satisfy the guard |
| `terraform init` | `Terraform has been successfully initialized!` | Backend and provider setup completed locally |
| `terraform fmt -check` | No output; exit 0 | Files are canonically formatted |
| `terraform validate` | `Success! The configuration is valid.` | HCL and provider schema are coherent |
| `terraform providers` | AWS requirement `~> 5.0` | The configuration declares the dependency |
| `terraform plan` | `No changes.` | There are no managed resources |

`init` success is a local dependency result, not an AWS permission test. `validate` success means the configuration is syntactically and semantically coherent against the installed provider schema; it does not mean the provider is configured or that AWS will accept a future deployment. `providers` lists requirements; it does not authenticate. `plan` with no resources is expected to be empty. If any command behaves differently, use the troubleshooting table before changing files.

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `Unsupported Terraform Core version` | The running Terraform is older than 1.12.0 | Install 1.12.x. Do not loosen the guard to hide the mismatch. |
| `Inconsistent dependency lock file` | The configuration constraint excludes the locked 5.100.0 | Restore the constraint, or run `init -upgrade` deliberately in a branch or scratch copy. |
| `Failed to query available provider packages` or a network timeout | Registry access, proxy, or connectivity problem | Retry, check connectivity, or reuse an existing cache. |
| `Missing required provider` or “provider not installed” | `init` has not run in this directory | Run `terraform init` before `validate` or `plan`. |
| `No configuration files` | Wrong working directory | Check `pwd` and `ls`; run the commands from `labs/w01/lab0-init`. |
| `fmt -check` prints filenames | Files are not canonically formatted | Run `terraform fmt`, then re-run `fmt -check`. |
| `validate` fails after an edit | Invalid HCL, an unknown argument, or a broken reference | Read the error, revert the edit, or fix the configuration. |
| `plan` asks for a region or credentials | You added a resource or data source that needs AWS | This lab has none. Remove the addition or configure credentials in a separate exercise. |

## Costs and safety

Nothing in this directory can create an AWS resource. `init` may contact the provider registry, not AWS; `fmt`, `validate`, and `providers` work from local files and the installed schema; `plan` has no resources to propose. Expect **$0.00** in AWS charges. The only resources consumed are network transfer and disk for the provider package. Do not create an IAM access key for this lab; you do not need one.

Git hygiene is the main safety practice here:

- Commit `main.tf`, `.terraform.lock.hcl`, and `README.md`.
- Do not commit `.terraform/`: it contains platform-specific binaries and can be regenerated.
- Do not commit state or plan files. In real projects they can contain sensitive values.
- Do not hand-edit the lock file or disable checksum verification. The hashes are the supply-chain check.
- Do not add a `cloud` block or an HCP Terraform token here. That changes the backend and authentication model, and it belongs to the HCP module.
- `rm -rf .terraform` is safe only for this cache. Never use a broad delete to “clean up” a Terraform directory.
- If you add resources later, use environment variables for credentials, grant least privilege, review the plan, and destroy what you create.

The lock file is safe to commit: it contains provider versions and hashes, not credentials. The state file is not safe to publish: it can contain sensitive attribute values. This lab has no state, but the habit starts now.

## Check your understanding

1. What does `required_version` actually check, and what does it not do?
2. What is the difference between `required_providers` and a `provider "aws"` block?
3. What does `~> 5.0` allow, and why is 6.0 excluded?
4. Why commit `.terraform.lock.hcl` but not `.terraform/`?
5. Why do `init`, `validate`, and `providers` not need AWS credentials here?
6. What changes if you add an `aws_s3_bucket` resource?
7. Does the lock file pin Terraform Core or modules?

**Answers:**

1. It checks that the running Terraform Core satisfies the constraint when a command loads the configuration. It does not install, download, or upgrade Terraform.
2. `required_providers` declares which provider package `init` must install and which versions are acceptable. A `provider "aws"` block configures that provider with settings such as region and credentials. This lab has no resources, so it needs the requirement but not the configuration.
3. `~> 5.0` accepts versions from 5.0.0 up to, but not including, 6.0.0. A 6.0 release is a new major version and may contain breaking changes. The lock selects the exact 5.100.0 within that range.
4. The lock is small, portable, and records the exact selection plus integrity hashes. The cache contains platform-specific binaries, can be large, and is regenerated by `init`.
5. `init` deals with provider packages from the registry, while `validate` and `providers` read local configuration and schema. `plan` has no resources, so no AWS API call is expected.
6. The provider would need a region and credentials, `plan` might read AWS state or data sources, `apply` could create billable resources, and a state file would appear. Cleanup would then require `destroy`.
7. No. `required_version` is the only Core constraint, and module versions come from their source declarations. The dependency lock file covers providers.

## Cleanup and reset

There is nothing to destroy because no resources were created. If you want to reset the local cache, run `rm -rf .terraform` from this directory and then `terraform init` again. Keep `.terraform.lock.hcl`.

If a `terraform.tfstate` appears after an experiment, inspect it before deleting it. This lab should not produce one with managed objects, but do not publish it or commit it. Remove any scratch directories created in Experiment 3.

## What's next

This lab stops at the working-directory boundary. Continue with the rest of Lesson 0 — credentials, repository conventions, auxiliary tools, and HCP Terraform — and then move to the next lab in this module. When resources enter the picture, the same lock/cache/state distinctions still matter, but the cost and safety rules change: plan before apply, review the plan, and destroy what you create.

Do not mark Lesson 0 complete from this lab alone. The lesson's own sections and question bank still apply.

## Verification

This guide is based on static inspection: `main.tf`, `.terraform.lock.hcl`, the `.terraform/` tree, `labs/.gitignore`, Lesson 0, and the tutoring contract were read. Terraform was not run, the provider registry was not contacted, and no AWS account was touched. The locked version 5.100.0, the `~> 5.0` constraint, and the `darwin_arm64` cache path are direct observations from this working copy. Expected command output is inferred from the configuration and Terraform behavior; exact wording varies by version and platform. All references are local to this repository.
