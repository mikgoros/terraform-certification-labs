# Lab 5 — A first AWS project

This lab connects several Terraform building blocks into one small AWS environment: a VPC and public subnet, an internet gateway and route, a security group, an EC2 instance, an IAM role with an instance profile, and an S3 bucket. Two data sources look up the current AWS account and a recent Ubuntu 22.04 AMI. The interesting part is not any single resource; it is the dependency graph that Terraform derives from the references between them.

The configuration is a teaching artifact, not a production baseline. It leaves out several things a real service would need, including a key pair, a bootstrapped application, a web server, tighter network exposure, and bucket-scoped IAM permissions. Those omissions are useful: they make the Terraform mechanics visible and give you concrete things to inspect before deciding what to add.

## What the configuration builds

```text
                         Internet
                             │
                    ┌────────▼────────┐
                    │ Internet Gateway│
                    └────────┬────────┘
                             │ 0.0.0.0/0
                    ┌────────▼────────┐
                    │ Public route    │
                    │ table           │
                    └────────┬────────┘
                             │ associated with
                    ┌────────▼────────┐
                    │ Public subnet   │
                    │ 10.0.1.0/24     │
                    │ us-east-1a      │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐        ┌──────────────────┐
                    │ Security group │        │ IAM role         │
                    │ ingress TCP 22 │        │ SSM + S3 read    │
                    │ from 0.0.0.0/0 │        └────────┬─────────┘
                    └────────┬────────┘                 │
                             │                  instance profile
                    ┌────────▼────────┐                 │
                    │ EC2 t3.micro    │◄────────────────┘
                    │ Ubuntu 22.04    │
                    └────────┬────────┘
                             │ temporary credentials
                    ┌────────▼────────┐
                    │ S3 bucket       │
                    │ account-id name │
                    └─────────────────┘
```

### The network path

The VPC (`10.0.0.0/16`) is the container for the subnet, security group, and route table. The public subnet (`10.0.1.0/24`) is pinned to `us-east-1a` and sets `map_public_ip_on_launch = true`, so an instance launched there receives a public IPv4 address. The internet gateway attaches to the VPC, and the public route table sends `0.0.0.0/0` to that gateway. The route table association is the piece that actually binds the subnet to the table.

That last resource matters more than it looks. Without the association, the subnet would fall back to the VPC's main route table, which has no route to the internet gateway. The subnet would still have a CIDR and an instance could still receive an address, but it would not have the working path to the internet that the diagram suggests. The configuration therefore builds four separate pieces — gateway, route table, route, association — to make the path explicit.

The security group is the only declared firewall control. It allows inbound TCP 22 from every IPv4 address (`0.0.0.0/0`) and all outbound traffic. Security groups are stateful, so return traffic for an allowed connection is permitted automatically. There is no HTTP or HTTPS ingress rule, and no custom network ACL is declared.

### The identity path

EC2 does not use a role directly. The configuration builds the canonical three-object chain:

1. `aws_iam_role.ec2_ssm` has a trust policy that lets the EC2 service assume it (`sts:AssumeRole` with `Service = "ec2.amazonaws.com"`).
2. Two `aws_iam_role_policy_attachment` resources attach AWS-managed policies to that role: `AmazonSSMManagedInstanceCore` for Systems Manager and `AmazonS3ReadOnlyAccess` for S3 reads.
3. `aws_iam_instance_profile.ec2` wraps the role, and the instance receives the profile through `iam_instance_profile`.

At runtime the instance obtains temporary credentials from the EC2 metadata service. No access key is written into the instance, the AMI, or the Terraform configuration. That is the important design point: the permissions travel with the instance identity, not with a static secret.

The trust policy is narrow, but the attached permissions are not bucket-scoped. `AmazonS3ReadOnlyAccess` is an AWS-managed policy that grants read access across S3 resources in the account; it is read-only, but it is broader than "read this one bucket." The SSM policy is also a managed policy with the permissions Systems Manager needs. Both are reasonable teaching shortcuts and poor production defaults.

### Compute and storage

The AMI is not hardcoded. `data "aws_ami" "ubuntu"` asks AWS for the most recent image owned by Canonical that matches the Ubuntu 22.04 amd64 name pattern and the HVM virtualization type. The instance uses `t3.micro`, the public subnet, the security group, and the instance profile. It has no `key_name` and no `user_data` block.

The S3 bucket name is `tf-assoc-lab5-assets-<account-id>`. The account ID comes from `data "aws_caller_identity" "current"`, which calls STS and returns the identity behind the credentials running Terraform. The suffix avoids the most common collision in S3, where bucket names share a global namespace. It is deterministic: the same account produces the same name on every plan, unlike a random suffix. The configuration does not declare public-access-block, versioning, or encryption settings; AWS account defaults and service defaults may still apply, so verify the bucket rather than assuming its full security posture from this file.

## How the dependencies are formed

Terraform does not need a single `depends_on` in this configuration. Each argument that reads another resource's attribute creates an implicit dependency edge. The graph is acyclic, so Terraform can create independent branches in parallel and can reverse the edges for destruction.

| Resource | Reads from | Why the edge exists |
| --- | --- | --- |
| `aws_subnet.public` | `aws_vpc.main.id` | The subnet must belong to the VPC. |
| `aws_internet_gateway.igw` | `aws_vpc.main.id` | The gateway attaches to the VPC. |
| `aws_route_table.public` | `aws_vpc.main.id`, `aws_internet_gateway.igw.id` | The table belongs to the VPC and its default route points at the gateway. |
| `aws_route_table_association.public` | `aws_subnet.public.id`, `aws_route_table.public.id` | The association joins one subnet to one table. |
| `aws_security_group.web` | `aws_vpc.main.id` | The group is scoped to the VPC. |
| `aws_iam_role_policy_attachment.*` | `aws_iam_role.ec2_ssm.name` | The attachments need the role name. |
| `aws_iam_instance_profile.ec2` | `aws_iam_role.ec2_ssm.name` | The profile wraps the role. |
| `aws_instance.web` | `data.aws_ami.ubuntu.id`, `aws_subnet.public.id`, `aws_security_group.web.id`, `aws_iam_instance_profile.ec2.name` | The instance needs an image, a subnet, a firewall, and an identity. |
| `aws_s3_bucket.assets` | `data.aws_caller_identity.current.account_id` | The bucket name includes the account ID. |

The practical consequence is visible in a plan. The VPC, IAM role, and caller identity have no dependencies on each other, so Terraform may create or read them concurrently. The route table waits for the internet gateway; the association waits for both the subnet and the route table; the instance waits for the subnet, security group, profile, and AMI lookup. The bucket can be created independently of the network once the account identity is known. The instance does not wait for the route-table association, because it references the subnet rather than the association; the association can complete after the instance exists, and internet connectivity begins once both the route and the association are in place.

Two kinds of values behave differently:

- **Known at plan time:** the account ID, the AMI ID returned by the data source, and the bucket name built from them. The plan can show these values.
- **Unknown until apply:** the VPC ID, subnet ID, instance ID, and public IP. Terraform displays `(known after apply)` for these because AWS assigns them when the resources are created.

The data sources are reads, not managed resources. A plan marks them with `<=` and does not propose creating them. If the AMI lookup returns no result, the plan fails before any resource is changed, which is a cheap failure. The AMI is also a moving target: when Canonical publishes a newer matching image, a later plan can detect a different AMI ID and propose replacing the instance.

## What the files in this directory actually contain

The directory is a complete root module with local state:

| File | Contents |
| --- | --- |
| `versions.tf` | Terraform `>= 1.12.0`; AWS provider `~> 5.0`. The lock file pins the AWS provider at `5.100.0`. |
| `providers.tf` | One AWS provider in `us-east-1`. |
| `data.tf` | The Ubuntu AMI lookup and the current caller identity. |
| `main.tf` | Twelve managed resource blocks: VPC, subnet, gateway, route table, association, security group, role, two attachments, instance profile, EC2 instance, and S3 bucket. |
| `outputs.tf` | VPC ID, instance ID, public IP, and bucket name, without descriptions. |
| `terraform.tfstate` | Local runtime state, generated during use and not part of a fresh clone. |
| `terraform.tfstate.backup` | A possible local backup, not read by Terraform during normal operation. |

With empty state, a fresh plan proposes twelve resources. Existing resources outside that state can still cause name collisions. Do not publish state or backups: they can contain account identifiers, resource IDs, and other private operational data.

### Differences from the written walkthrough

The walkthrough and the configuration in this directory are close, but not identical. The differences matter when you compare expected output with what the files actually declare.

| Topic | Walkthrough | This directory |
| --- | --- | --- |
| SSH login | The SSH step assumes a configured key pair and passes `-i` to a private key. | `aws_instance.web` has no `key_name`. There is no key pair attached, so the configuration alone provides no SSH authentication method. |
| Web server | The instance is called `web` and the walkthrough uses it as the place to run commands. | There is no `user_data`, no HTTP or HTTPS ingress, and no application bootstrap. The name is a label; no web server is installed or started. |
| Resource count | The example plan comment says `Plan: 10 to add`. | `main.tf` declares twelve managed resources. A clean plan against empty state should count twelve, plus two data-source reads. |
| IAM role name | The walkthrough shows `tf-assoc-lab5-ssm-role`. | The file uses `tf-assoc-lab5-ec2-ssm-role`. |
| Security-group description | The walkthrough describes the rule as "SSH from anywhere (LAB ONLY)". | The file describes it as "Allow SSH inbound and outbound traffic", which is less explicit about the risk. |
| Outputs | The walkthrough shows descriptions on each output. | `outputs.tf` has values but no descriptions. |
| Root volume | The cost table assumes a 20 GiB gp3 root volume. | The instance does not override the AMI's root volume mapping, which can change with the selected AMI. |
| Trailing comment | Not present. | `main.tf` ends with `# comentario nuevo`, a harmless leftover from the saved-plan experiment. |

Two of these differences deserve emphasis because they change how the lab behaves, not just how it reads.

**No key pair.** An open port is not a login. The security group permits TCP 22, but the instance has no authorized public key from this configuration. A client can complete a TCP connection and still fail authentication. To use SSH you would need to create or import an EC2 key pair, add a `key_name` to the instance, and keep the private key outside the repository. Adding `key_name` changes the instance; inspect the plan to see whether Terraform proposes an in-place update or a replacement. The Systems Manager policy is the alternative path, but it is necessary rather than sufficient: the instance needs a working SSM agent, outbound connectivity to the service, and a caller with permission to start a session.

**No web server.** A public IP address and an internet route make the instance reachable at the network layer. They do not create a website. There is no process configured to listen on port 80 or 443, and those ports are not open. A browser request to the public IP has nothing to answer it. If you want a web server, you must add the bootstrap and the ingress rule yourself, and then treat the result as a new design decision rather than a missing line in this lab.

## Before you deploy

- Use Terraform 1.12.0 or newer, network access to the provider registry, and AWS credentials with permissions for EC2, VPC, IAM, S3, and the two data-source calls.
- Confirm the target account and region. The provider is fixed to `us-east-1`, and the subnet is fixed to `us-east-1a`.
- Prefer an isolated learning account. The security group opens SSH to all IPv4 addresses, the IAM policies are broad managed policies, and the resources have fixed names that can collide with leftovers from a previous run.
- Review the plan before applying. The plan contacts AWS for the AMI and caller identity, so it needs credentials even though it creates nothing.
- Treat the state and the saved plan as private. Do not commit them, and do not paste their contents into a public issue or chat.
- Set a budget or billing alarm before creating the instance if you are sensitive to cost. The estimate below is a planning aid, not a quote.

## Experiments

These experiments are ordered from static inspection to optional deployment. The first four do not create resources; the last three require an apply and therefore incur cost.

### 1. Read the plan before creating anything

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform show tfplan
```

With an empty state, expect the plan to propose creating twelve managed resources and to read the two data sources. The AMI ID and bucket name should be known; identifiers assigned by AWS — the VPC, subnet, security group, and instance IDs — plus the public IP should be unknown until apply. `terraform fmt -check` reports whether the files are canonically formatted without rewriting them; `terraform validate` checks syntax and internal references but does not prove that AWS will accept the deployment or that your credentials have every permission.

The saved plan is bound to the exact configuration that produced it. If you edit a file and then run `terraform apply tfplan`, Terraform should reject the plan as stale. That is why the trailing comment in `main.tf` exists: it was used to demonstrate the stale-plan check. Re-run `terraform plan` after any edit instead of forcing an old plan.

### 2. Trace the dependency graph

```sh
terraform graph
```

The output is Graphviz DOT, which you can read as text even without rendering it. Look for the edges from the VPC to the subnet, gateway, route table, and security group; the edge from the gateway to the route table; the edges from the subnet and route table to the association; the edges from the role to the attachments and profile; and the edges from the subnet, security group, profile, and AMI to the instance. The bucket should connect only to the caller-identity data source.

This is the clearest way to see why the configuration does not need `depends_on`. The references are the dependencies.

### 3. Change a referenced value without applying

Change the public subnet CIDR from `10.0.1.0/24` to `10.0.1.0/25`, run `terraform plan`, and then revert the edit. Do not apply this change.

Expect the plan to propose replacing the subnet, the route-table association, and the EC2 instance. The subnet CIDR change forces a new subnet; the association references the subnet ID, so it must be replaced as well; the instance references the subnet ID, so it cannot stay in place. The VPC, gateway, route table, security group, IAM resources, and S3 bucket should be unaffected. That pattern — one changed attribute propagating only along the reference edges — is the practical meaning of the dependency graph.

### 4. Inspect the IAM boundary

These read-only calls require permission to inspect IAM:

```sh
aws iam list-attached-role-policies \
  --role-name tf-assoc-lab5-ec2-ssm-role
```

Expect two AWS-managed policies: `AmazonSSMManagedInstanceCore` and `AmazonS3ReadOnlyAccess`. Then inspect the S3 policy and note that its resource is `*`, not the ARN of the lab bucket. The role can read objects in every bucket in the account that the policy covers. It cannot write or delete, which is why the lab calls it read-only, but "read-only" is not the same as "least privilege for this bucket." A production replacement would use a customer-managed policy scoped to `aws_s3_bucket.assets.arn` for `s3:ListBucket` and to `aws_s3_bucket.assets.arn/*` for `s3:GetObject`.

### 5. If you apply: separate reachability from authentication

After `terraform apply` and `terraform output`, test the network path and then the login path:

```sh
ssh -o ConnectTimeout=5 ubuntu@"$(terraform output -raw web_instance_public_ip)"
```

A TCP client such as `nc` can confirm that port 22 is reachable. SSH itself should fail authentication because no key pair is attached; the typical result is `Permission denied (publickey)`, though the exact message depends on the client and server configuration. This is the expected finding, not a broken instance. The security group opened the port; the instance never received a key.

If you want to test the intended alternative, try Systems Manager:

```sh
aws ssm start-session --target "$(terraform output -raw web_instance_id)"
```

This only works if the SSM agent is present and running, the instance can reach the service, and your local identity has permission to start the session. The attached policy is one part of that chain, not a guarantee.

### 6. If you apply: verify the role and the read-only limit

Inside a working session on the instance, list the bucket:

```sh
aws s3 ls
```

The role should allow the bucket to appear. Reading is allowed; writing is not. An upload attempt should fail with an access-denied error, which demonstrates the boundary of `AmazonS3ReadOnlyAccess`. If `aws s3 ls` itself fails, debug in order: is the instance profile attached, does the role trust EC2, and are the policy attachments present? That sequence is more reliable than guessing at the S3 bucket policy, because this lab does not declare one.

### 7. If you apply: observe drift

Change the `Environment` tag on the instance in the AWS console from `dev` to `manual-drift`, then run `terraform plan`. Expect an in-place update that proposes returning the tag to `dev`. Running `terraform apply` restores the configured value.

`terraform apply -refresh-only` is a different operation: it records the observed value in state without changing the configuration. A later plan will still propose returning to the configured value unless you also edit the configuration. Use the normal apply when you want Terraform to enforce the declared state; use refresh-only when you are deliberately inspecting or accepting reality before deciding what the configuration should say.

## Practice

The experiments above are the hands-on part of the lab. This closing exercise checks that you can explain the configuration without deploying it.

### Exercise 1 — Explain the graph and the gaps

**Objetivo (objective):** Explain the dependency graph and identify what the lab does not provide.

**Pasos (steps):** Without applying, read `main.tf` and `data.tf`. Choose five references and state which resource must exist first. Then list the missing key pair, the missing web server, the open SSH rule, and the broad S3 policy.

**Expected result:** A short explanation that names the VPC-to-subnet-to-instance chain, the IAM-role-to-profile-to-instance chain, and the account-ID-to-bucket-name edge, plus the gaps and their consequences.

**Solution:** The dependency table and the "Differences from the written walkthrough" section above contain the expected answer. A strong answer also notes that the instance does not wait for the route-table association.

**Criterios (criteria):** You can explain each edge without `depends_on`, and you can say why an open port is not a login.

## Cost

The network resources — VPC, subnet, internet gateway, route table, association, and security group — have no hourly charge in this design. The billable pieces are the running EC2 instance, its root EBS volume, the public IPv4 address, and any S3 storage, requests, or data transfer you add.

| Item | This configuration | Cost behavior |
| --- | --- | --- |
| EC2 `t3.micro` | Created | On-demand hourly charge while running; Free Tier eligibility depends on the account and date. |
| Root EBS volume | Implicit from the AMI | Storage charge; the size and type depend on the selected AMI. |
| Public IPv4 | Assigned by the subnet | May be billed separately under current AWS pricing. |
| S3 bucket | Created empty | No object storage while empty; requests and data transfer if used. |
| NAT gateway | Not created | Avoided; a NAT gateway would add an hourly charge and data-processing cost. |
| Elastic IP | Not created | Avoided; the instance uses a dynamic public address. |

Prices vary by region, date, AMI mapping and account; the public IPv4 charge is easy to forget. Check current pricing for your account before leaving anything running. Destroy the lab when you finish rather than relying on a historical estimate.

## Cleanup

Run the destruction from this directory and review its plan:

```sh
terraform destroy
```

If the bucket contains objects, destruction fails because S3 will not delete a non-empty bucket. Empty it first:

```sh
aws s3 rm "s3://$(terraform output -raw assets_bucket_name)" --recursive
terraform destroy
```

`aws s3 rm --recursive` removes current objects, but it does not remove noncurrent versions or delete markers. If versioning was enabled manually, remove those separately with the S3 console or a lifecycle rule before retrying. The `aws s3 rm` command is safe only after you have confirmed the bucket name belongs to this lab. Do not remove unrelated buckets, roles, or network resources that happen to share a similar name.

After destruction, verify the result instead of trusting the command's exit status:

```sh
terraform state list
```

The list should contain no managed resources; if data sources remain in state, they are read-only records rather than live infrastructure. In AWS, confirm that the EC2 instance is terminated, the VPC and its gateway, route table, association, subnet, and security group are gone, the IAM role, its two attachments, and the instance profile are gone, and the S3 bucket no longer exists. Check for an orphaned root EBS volume if the instance did not terminate cleanly; the AMI marks the root device for deletion on termination, but a failed termination can leave storage behind.

If an apply fails partway through, the fixed IAM and security-group names can collide on the next attempt while the main state may not know about the partially created resources. Inspect the account, remove only the lab's leftovers, and re-plan. Keep `terraform.tfstate` and `terraform.tfstate.backup` private throughout; neither belongs in a public repository.

## Verification

This guide is based on static inspection of the configuration and state files in this directory. The commands and the AWS deployment were not executed for this documentation. The main state currently records no resources, so the expected plan counts and the resource inventory come from the configuration, not from a live account. Provider behavior, IAM evaluation, current pricing, AMI selection, and the availability of Systems Manager must be verified in your own environment.
