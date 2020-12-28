# Table of Contents

- [Table of Contents](#table-of-contents)
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Our network layout](#our-network-layout)
  - [Requirements](#requirements)
  - [VPC](#vpc)
  - [Subnets](#subnets)
  - [Resource Graphs and Exported Attributes](#resource-graphs-and-exported-attributes)
  - [The Execution Plan](#the-execution-plan)
  - [Routing](#routing)
  - [Refactoring](#refactoring)
  - [Security](#security)
  - [Compute](#compute)
  - [Apply](#apply)
  - [State Management](#state-management)
  - [Destroy](#destroy)
- [Further considerations](#further-considerations)
- [Further reading](#further-reading)
- [Wrap up](#wrap-up)

# Overview

Infrastructure-as-code consists in the ability to transform a given set of requirements into code that defines a network with all of its components and connections. Terraform is a tool for building, changing and versioning infrastructure. It enables us to do infrastructure management and automation with code, and since Terraform can manage low-level components such as compute instances, storage, and networking, as well as high-level components like Domain Name Server (DNS) entries, Software Defined Networking (SDN) is one of the many use cases of Terraform. SDN is way much more than what we'll do today but by the end of this post we'll have a blue print of a three-tier network in AWS that we can use as a base to build on top of.

Each tier will be represented by a subnet: a public subnet and two (2) private subnets.  The private subnets are meant to be used by an application layer and a database layer. The public subnet is where we'll execute our administration tasks and where all public traffic is routed to. For our admin tasks, we'll launch an EC2 instance in the public subnet and use it as a jump box to connect to an EC2 instance deployed in the application layer. This centralizes access to our private subnets and gives us ability to do system updates and debugging on instances deployed therein.

Creating a custom Virtual Private Cloud (VPC) with all of its components is one of the first things I learned to do in the AWS Console. However, it became cumbersome and time-consuming to create, update and/or destroy resources all the time because it involved a lot of point-and-click, tedious, and manual work. There are quite a few tools out there to automate this process or do infrastructure-as-code, such as the AWS Command Line Interface (CLI), the AWS Software Development Kit (SDK) and Cloud Development Kit (CDK), AWS CloudFormation, Pulumi, and others; nevertheless, I find Terraform straightforward and easy to use, it has a great community, strong ecosystem, it's open source and it's backed by HashiCorp.

# Prerequisites

## Dependencies

First and foremost, we'll need to have [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/aws-get-started) and the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) installed, as well as an active AWS account. Please refer to the official documentation to do so. Installing Terraform on Linux and macOS is easier, but if you're on Windows, I'd recommend installing Terraform using [Chocolatey](https://chocolatey.org/packages/terraform) (because it is easier).  If you can't figure it out reach out in the comments section and I'll try my best to help out.

## Configuration

In a new directory, open up your favorite editor and create a file named `main.tf`. In this file, let's define a couple of things we need to get started: a `terraform` configuration block and a `provider` configuration block. Inside the `terraform` block we'll need to specify our provider requirements by using a `required_providers` block. This block consists of a local name, a source location and a version constraint. Let's look at the following example.

```terraform
terraform {
  required_providers {
    local_name = {
      source  = "source_name"
      version = "version_constraint"
    }
  }
}
```

The above-mentioned snippet is to indicate where things go, it wouldn't work like that because we'll need to use a real provider. Since we're going to interact AWS we'll need to use an AWS provider for that. You might be wondering what a provider is (I know because I'd be too) and we'll get to that soon, but what's important here is to understand that this configuration will trigger Terraform to download and install this [particular provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) named `hashicorp/aws` and found in the [Terraform Registry](https://registry.terraform.io/browse/providers).

Now that we know the required nomenclature, let's proceed with defining it.

```terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}
```

Next, we'll use the `provider` block to configure our AWS provider, and refer to it as "aws" because that is the name we used as the **local name** in the `required_providers` block above. The local name is what Terraform uses as a reference to that specific provider and therefore should be unique within a module.  With that being said, we're using the string "aws" because it is both a convention and the provider's *preferred local name* (we could have named it something else).

```terraform
provider "aws" {}
```

Inside the `provider` block we'll insert all of our module-specific configuration instructions. We can view both required and optional arguments available to the provider in reference [herein](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#argument-reference). A quick scan of this document tells us that there are no required arguments; however, since some arguments **are needed** by the provider in order to fulfill its main responsibility of interacting with AWS on your behalf, they must be sourced from somewhere.

For instance, don't we need user credentials and a region in order to do anything within AWS? The provider will try to obtain these from their default location if not provided. Given we submit an empty `aws` provider block or we don't specify `access_key` and `secret_key` in our configuration block, our credentials will be sourced from it's usual location `~/.aws/credentials`. However, Terraform can also source the credentials from environment ariables or shared credentials.

Although the above could work, let's be specific about the region:

```terraform
provider "aws" {
  region = "us-east-1"
}
```

We can now conclude our initial configuration phase and instruct Terraform to download and install the `aws` provider, as well as any other provider needed, by issuing the following command in the terminal from the root directory of our project: `$ terraform init`.  This initializes a working directory containing Terraform files and it is the first command that should be run after writing a new Terraform configuration, see [here](https://www.terraform.io/docs/commands/init.html).

A palpable consequence of running the `init` command is the appearance of a new `.terraform` folder in your root directory, in addition to a `.terraform.lock.hcl` file. The `.terraform` directory is a local cache used by Terraform to retain files it will need for future operations, see [here](https://stackoverflow.com/a/59289696/7076186). The lock file is a dependency lock file for various items cached in the aforementioned directory, see [here](https://www.terraform.io/docs/configuration/dependency-lock.html). I'd advise to inspect the directory and files to get a sense of their contents but it's not necessary. What I'd like you to do though is take advantage of a very useful command: `$ terraform fmt` rewrite our Terraform code in accordance to Terraform language style conventions, see [here](https://www.terraform.io/docs/commands/fmt.html). It certainly helps tidy things up and it's good to run it as part of a Continuous Integration (CI) pipeline.

By the way, before we continue, aren't you curious to know what what would happen if we don't specify a required provider or provider configuration block? Well, Terraform would still figure out that we need to download and install because by convention the resource block, which we'll see later, start with a provider's *preferred local name*, i.e. `aws_vpc` or `aws_subnet` both start with `aws`. You can test it out by deleting the recently generated `.terraform` directory, `.terraform.lock.hcl` file, and `required_providers` block, then reinitialize with `$ terraform init`.

# Our network layout

We can create a VPC by defining  it ourselves from scratch using `resource` blocks provided by the `aws` provider or by using an available module like [this one](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest/examples/complete-vpc), that takes in a set of required and optional variables to create a variety of resources (infrastructure objects) typically found in a VPC, which would otherwise need to be created individually using a combination of `resource` blocks. A `resource` is the most important element in the Terraform language. It's equivalent to a Lego piece.

Despite the existence of community modules and taking into consideration that our goal is to have a deeper understanding of Terraform and AWS, we'll take the road less travelled approach and code everything from scratch. This will foster our appreciation of all readily available modules created by the community and give us a much needed know-how in reading documentation and tweaking configuration files to our desire.

## Requirements

Most of the time we have two forms of requirements: the ones that are explicitly mentioned and the ones that are implied. In other words, if one is given a list of explicit requirements like the ones found below, one should be able to know that in order to do *x* we'll need *y*.

### Explicit requirements

1. The VPC should have an IPv4 CIDR block of `172.16.0.0/16` (translates to 65,356 IP addresses).
2. One (1) public subnet and two (2) private subnets spread out in one (1) availability zone. The public subnet's CIDR block is `172.0.1.0/24` and the private subnets' CIDR blocks are `172.0.2.0/24` and `172.0.3.0/24`.
3. One (1) EC2 instance must be deployed in the public subnet.
4. One (1) EC2 instance must be deployed in the private subnet.
5. Ability to connect to our EC2 instance (the jump box) in the public subnet via SSH.
6. Ability to connect to our EC2 instance in the private subnet only from the jump box.
7. Ability to perform updates on our instances.
8. Keep costs free or as low as possible.

### Implicit requirements

There are also implied requirements that weren't explicitly mentioned:

1. In order to access our VPC from the internet to connect to our jump box instance we need an Internet Gateway attached to our VPC, a Route Table and Route Table Association that routes traffic between the Internet Gateway and the public subnet, and a public IP address assigned to our EC2 instance.
2. In order to perform updates from within the EC2 instance deployed in the private subnet, we need to create a Network Address Translation (NAT) Gateway that'll reside in the public subnet and assign an Elastic IP (EIP) to it.
3. We'll also need at least two (2) security groups assigned to our instance in the public subnet and private subnet. The former needs to allow SSH access from anywhere and the latter needs to allow SSH access from the former's Security Group. Both of the security groups in reference also need to allow outbound HTTP traffic on port 80 so we can perform updates. Note that a common characteristic of Security Groups is that they are *stateful*, meaning that *a response to an outbound request will be allowed to enter as inbound traffic* only if the request was initiated from within the Security Group in reference.
4. To keep it in the free tier, our EC2 instance types will be `t2.micro`.

### A Diagram of our Requirements

They say a picture is worth a thousand words, so let's use that to our advantage and create a visual representation of our requirements. I used an AWS template from Lucid Chart to do the following diagram, feel free to grab a copy of the diagram [here](https://lucid.app/lucidchart/invitations/accept/85f9ace8-c55d-420b-8a53-01a76435d4c6).

![SDN AWS Horizontal Framework(3)](C:\Users\adriaanbd\Downloads\SDN AWS Horizontal Framework(3).png)

## VPC

Now that we're clear on what we're building, it's time to get our hands dirty. Let's start at the top with the VPC and move down gradually. we'll be hard coding some values into our resources but we'll have an opportunity refactor later. This gives us a chance to introduce Terraform gradually and gives us additional perspective.

Terraform does a fantastic job at providing detailed documentation, so let's check out the docs for the VPC resource [here](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc). By default, all VPC's and subnets must have an IPv4 [CIDR block](https://docs.netgate.com/pfsense/en/latest/network/cidr.html#where-do-cidr-numbers-come-from), which is a method for allocating IP addresses introduced in 1993 by the Internet Engineering Task Force (see [here](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing)). Thus, it's not a surprise that `aws_vpc`'s [Argument Reference](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc#argument-reference) indicates that we are required to submit a CIDR block to create a VPC.

Let's use one of AWS' recommended [IPv4](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-ip-addressing.html) CIDR blocks for [VPC and subnet sizing](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html#vpc-sizing-ipv4): `172.16.0.0/16`, which translates to 65,536 IPv4 addresses that'll be assigned to our VPC. This doesn't mean we actually have 65,536 addresses at our disposal, just 65,531. AWS will reserve the first four and last address (i.e. `172.16.0.0`, `172.16.0.1`, `172.16.0.2`, `172.16.0.3`, `172.16.0.255`). If you're somewhat confused about CIDR's, here's a CIDR to IPv4 conversion [tool](https://www.ipaddressguide.com/cidr) to the rescue.

We can create a VPC with the configuration code shown below. Notice the use of [resource tags](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/resource-tagging), a useful practice to assign metadata to your AWS resources. Read [here](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html) for more information about tagging AWS resources.

```terraform
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Project = "sdn-tutorial"
  }
}
```

## Subnets

Now that we've defined our virtual network within AWS, let's proceed to define our public and private subnets. According to the [Attribute Reference](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) of an `aws_subnet` resource, the two required arguments consist of a CIDR block, as we saw before, and the VPC id of where this subnet would be located. In addition to that, we'll go ahead and specify the availability zone as well and  switch the `map_public_ip_on_launch` option to `true` in our public subnet. We want EC2 instances that are launched in this subnet to have a [public facing IP address](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-ip-addressing.html#vpc-public-ipv4-addresses) and for the assignment to happen automatically on launch (which is part of the reason why it is a public subnet).


```terraform
resource "aws_subnet" "pub_sub" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Project = "sdn-tutorial"
  }
}

resource "aws_subnet" "prv_sub" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "172.16.4.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Project = "sdn-tutorial"
  }
}
```

## Resource Graphs and Exported Attributes

Before we continue I'd like to address how the `vpc_id` required by the subnet is obtained by the subnet resource because it relies on an important feature of Terraform in regards to resources: [dependency graphs](https://www.terraform.io/docs/internals/graph.html) and [exported attributes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc#attributes-reference). In case you didn't know, Terraform [builds a dependency graph](https://www.terraform.io/docs/internals/graph.html#building-the-graph) of all our resources in order to create and modify them as efficiently as possible in a logical sequence. It does this by [walking the graph](https://www.terraform.io/docs/internals/graph.html#walking-the-graph) in parallel using a standard [depth-first traversal](https://en.wikipedia.org/wiki/Depth-first_search) wherein a node is considered *walked* when all of it's dependencies have been seen. You don't need to know exactly how it works, but it's good to be aware of it at a high level.

The key takeaway of this is that Terraform maps out the logical inter-dependency of all our resources before it actually takes any action on them. In other words, Terraform knows that it needs to create the VPC resource first and use its exported attribute as an input to the subnet resource. There is more to know about about inputs and outputs in Terraform but we'll look at that later. The exported attributes of a resource are in the [Attributes Reference](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc#attributes-reference) section of the resource's documentation.

## The Execution Plan

We've come to that point where we have enough and would like to see what actions will be taken by Terraform to create our desired infrastructure. For that to happen we can execute the following command `$ terraform plan`. This is a way for us to check whether the plan matches our expectations. In this case, it'll produce an output similar to the one below.

```shell
An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_subnet.prv_sub will be created
  + resource "aws_subnet" "prv_sub" {
      + arn                             = (known after apply)
      + assign_ipv6_address_on_creation = false
      + availability_zone               = "us-east-1a"
      + availability_zone_id            = (known after apply)
      + cidr_block                      = "172.16.4.0/24"
      + id                              = (known after apply)
      + ipv6_cidr_block_association_id  = (known after apply)
      + map_public_ip_on_launch         = false
      + owner_id                        = (known after apply)
      + tags                            = {
          + "Project" = "sdn-tutorial"
        }
      + vpc_id                          = (known after apply)
    }

  # aws_subnet.pub_sub will be created
  + resource "aws_subnet" "pub_sub" {
		...
    }

  # aws_vpc.main will be created
  + resource "aws_vpc" "main" {
		...
    }

Plan: 3 to add, 0 to change, 0 to destroy.
```

It's really interesting to observe that the first resource on the list is the last resource in our configuration. As a matter of fact, the resources are in reverse order compared to how we defined them in our file. Why do you think that is? *Hint*: *dependency graph*. Feel free to comment in the comments section.

Another thing to note are all the `+` symbols indicating that the resource will be created and that the lines have been added, as opposed to deleted or modified. Reading the execution plan in reference provides a sense of reassurance that we're on the right track.

## Routing

We need to build all of the plumbing in our virtual network: Internet Gateway, Route Tables and NAT Gateways. These are the main components that'll enable communication to and within our network. We'll begin with the internet gateway because it's what allows communication between our VPC and the rest of the world.

### Internet Gateway

This component acts as a centralized target attached to our VPC in order to route traffic between our subnets and the internet, hence the name gateway. It also performs [network address translation](https://en.wikipedia.org/wiki/Network_address_translation) for instances that have been assigned a public IP address. To gain a deeper understanding of an internet gateway read [here](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html), as it's certainly helpful information on AWS internals.

Within `hashicorp/aws` provider documentation we see that, like our subnets, the only required argument is `vpc_id`.

```terraform
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Project = "sdn-tutorial"
  }
}
```

### Public Subnet Route Tables and Associations

Route tables are used to control where network traffic is directed. Each subnet needs to be associated with a route table. A VPC comes with a main route table by default and controls the routing for all subnets that are not explicitly associated with any other route table. Since we'd like to be explicit with our associations  and do not want the default behavior implied with not associating our subnet to a route table, we need to create a [custom route table](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html#CustomRouteTables) and a [subnet route table association](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html#route-table-assocation). This allows routing from our public subnet to our internet gateway. We can use their corresponding Terraform resources: `aws_route_table` and `aws_route_table_association`. Required arguments for the [first](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) is the `vpc_id` and for the [latter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association#argument-reference) is `route_table_id`.

Furthermore, since a route table is a set of rules, called routes, we'll need a rule that directs traffic from anywhere `"0.0.0.0/0"` to the internet gateway. We can use the route object implemented as an [attribute-as-block](https://www.terraform.io/docs/configuration/attr-as-blocks.html?_ga=2.196141612.1805412045.1609091923-640873875.1609091923), which is an attribute that uses Terraform's block syntax. Many resources use this approach to manage sub-objects that are related to the primary resource.

```terraform
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Project = "sdn-tutorial"
  }
}
```

And our route table association that glues the subnet and the route table together.

```terraform
resource "aws_route_table_association" "rt_assoc" {
  subnet_id      = aws_subnet.pub_sub.id
  route_table_id = aws_route_table.pub_rt.id
}
```

We're done with the public subnet for now and we can move on to our private subnet's requirements. Specifically, we should only able to access the internet from within it (outbound traffic). Remember that we are not able to initiate connection from outside the VPC with our private subnet (inbound traffic), but if we want to perform updates in our instance we need to be able to talk to the outside world (outbound traffic). This is where the NAT gateway comes in.

### NAT Gateway and Elastic IP

A Network Address Translation (NAT) gateway is what enables an instance in a private subnet to connect to the internet (outbound) but prevents the internet initiating a connection with it (inbound). To create it, we [need to specify](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html#nat-gateway-basics) the public subnet in which it will reside and associate it with an [Elastic IP](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-eips.html) (EIP) address.

Since the EIP is required by the [NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html#nat-gateway-basics), let's define it first. Important to note that the order of resources in our configuration file is meaningless to Terraform, precisely because Terraform builds and walks a graph of our dependencies, as mentioned previously.

Here's the provider documentation for the [EIP](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) and [NAT gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway). Notice that the required arguments for an EIP are none but we will indicate the fact that it is located in a VPC. The required arguments of a NAT gateway are `allocation_id` and `subnet_id`. Allocation is the EIP that is allocated to it.

```terraform
resource "aws_eip" "nat_eip" {
  vpc = true

  tags = {
    Project = "sdn-tutorial"
  }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.pub_sub.id

  tags = {
    Project = "sdn-tutorial"
  }
}
```

### Private Subnet Route Tables and Associations

Now that we have our NAT gateway with an EIP assigned to it, we can define our private route table wherein there's a route that directs traffic to anywhere `"0.0.0.0/0"` through the NAT gateway, as opposed to the internet gateway. This doesn't mean that the internet gateway isn't used, on the contrary, once traffic reaches the NAT gateway in the public subnet, it will abide by the rules specified in the public route table.

```terraform
resource "aws_route_table" "prv_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Project = "sdn-tutorial"
  }
}

resource "aws_route_table_association" "prv_rt_assoc" {
  subnet_id      = aws_subnet.prv_sub.id
  route_table_id = aws_route_table.prv_rt.id
}
```

This concludes our plumbing work . We can now generate a new execution plan to see if it matches our expectations (`$ terraform plan`). It's also a good moment to think about the work we've done because there are about `105` lines of code in one file and it's starting to get crowded. Perhaps there is a better way to organize our code.

## Refactoring

Terraform is built around the concept of modules. A module is an abstraction that resembles a container for multiple resources that are used together. All of the `.tf` files in your working directory form the root module. Terraform loads all of the files in your root module together when generating the execution plan or applying the execution plan. This means we can separate our code into files to achieve some sort of separation of concerns. It's be easier to find things that way. For example, it's common to have a separate file for the required providers' version specifications and the provider configurations.

```terraform
# ./versions.tf
terraform {
  required_version = "~> 0.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# ./providers.tf
provider "aws" {
  region = var.region
}
```

Moreover, all of the resources we've defined are functionally related to the concept of a network. If we were to carry on further with adding the rest of the remaining resources, we'll have to add things related to computing (EC2 instances) and security (security groups). So, in a way, it makes sense to organize our code into files in terms of functionality. Let's do that by creating a file named `network.tf` and move over all of the resources we have in our configuration right now. We'll use this approach for the remaining components and then talk about alternatives.

Remember I stated we don't necessarily need a file named `main.tf`? Well, let's find out. Delete the empty `main.tf` and run `terraform plan`.

## Security

Our requirements state that SSH access is allowed into the instance in our public subnet and, similarly, SSH access is allowed into our instance in the private subnet, but *only if it comes from the jump box*. We can do this with security groups.

### Security Groups

A security group is a virtual firewall around an instance or component that controls inbound and outbound traffic. We can assig security groups to an EC2 instance. Each security group is composed of rules for inbound traffic and rules for outbound traffic. Gain a deeper understanding of them [here](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html#SecurityGroupRules).

There are two ways you can define your security groups in Terraform. One approach is to define all ingress and egress rules within a `aws_security_group` resource block. Another approach is to define both a [security group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group#argument-reference) and an `aws_security_group_rule` which represents a single ingress or egress rule that'd otherwise be in a security group resource. I usually prefer the latter approach but you can implement it however you want.

Since we need HTTP egress traffic in all of our instances to be able to perform updates, we'll create a general security group for this. Let's also use the "description" argument to explain it.

```terraform
# ./security.tf

resource "aws_security_group" "general_sg" {
  description = "HTTP egress to anywhere"
  vpc_id      = aws_vpc.main.id

  tags = {
    Project = "sdn-tutorial"
  }
}

resource "aws_security_group" "bastion_sg" {
  description = "SSH ingress to Bastion and SSH egress to App"
  vpc_id      = aws_vpc.main.id

  tags = {
    Project = "sdn-tutorial"
  }
}

resource "aws_security_group" "app_sg" {
  description = "SSH ingress from Bastion and all TCP traffic ingress from ALB Security Group"
  vpc_id      = aws_vpc.main.id
  tags = {
    Project = "sdn-tutorial"
  }
}
```

In regards to our security group rules, we have to be specific about the type of rule, i.e. ingress or egress, the origin and destination ports, the communication protocol, CIDR blocks where the traffic comes from and the security group it pertains to.

#### Egress rules

```terraform
# ./security.tf

resource "aws_security_group_rule" "out_http" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.general_sg.id
}

resource "aws_security_group_rule" "out_ssh_bastion" {
  type                     = "egress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion_sg.id
  source_security_group_id = aws_security_group.app_sg.id
}

resource "aws_security_group_rule" "out_http_app" {
  type              = "egress"
  description       = "Allow TCP internet traffic egress from app layer"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app_sg.id
}



```

#### Ingress rules

```terraform
# security.tf

resource "aws_security_group_rule" "in_ssh_bastion_from_anywhere" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "in_ssh_app_from_bastion" {
  type                     = "ingress"
  description              = "Allow SSH from a Bastion Security Group"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}
```

### SSH Keys

To access our instances, we'll need to register a key pair consisting of a private key and a public key. The key pair is used as a set of security credentials to prove our identity when connecting to an EC2 instance. The way this works is that Amazon EC2 stores the public key and we store the private key. We can use that instead of a password and anyone with the private key can connect to the instances, so it's really important to store them in a secure place. This also means we need to perform some tasks on our end: generate a key pair, send its public key to AWS, and keep the private key in our computer in a safe place.

We'll use the `hashicorp/tls` provider to generate a throwable key pair, see [here](https://registry.terraform.io/providers/hashicorp/tls/latest/docs). Specifically, we'll use the `tls_private_key` resource to generate a 4096 bit sized RSA key.

```terraform
# ./keys.tf

resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
```

We'll use the `aws_key_pair` resource from `hashicorp/aws` provider to send the public key in a file to AWS. We need to provide a key name and the contents of the public key data in a format that is [compatible](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#how-to-generate-your-own-key-and-import-it-to-aws) with Amazon EC2. One of the exported attributes from the `tls_private_key` is `public_key_openssh` that contains the public key data in OpenSSH `authorized_keys` format, thereby complying with AWS' requirements.

```terraform
# ./keys.tf

resource "aws_key_pair" "key_pair" {
  key_name   = "sdn_tutorial_key"
  public_key = tls_private_key.rsa_key.public_key_openssh
}
```

We also need to generate a file that has the contents of our private key. For this, we can use the `local_file` resource from the [Local](https://registry.terraform.io/providers/hashicorp/local/latest/docs) provider. This provider is used to manage local resources, like a file, and the `local_rile` resource is used to generate a file with desired content. In addition to that, if you've used SSH before, you're aware that proper file permissions are not only required but important. Particularly, we'd like Terraform to set the proper file permissions when we create our private key file.

To put it in perspective, to connect to our instance we'll need to:

1. Generate a key pair.
2. Send the public key to AWS.
3. Store the private key in a safe place.
4. Set proper file permissions on the private key file.
5. Add the key to our SSH keychain.

Since this is something we'll typically do in our shell or terminal by executing a series of commands, we can use the Terraform [Provisioners](https://www.terraform.io/docs/provisioners/index.html), particularly the `local_exec` provisioner, which executes a local executable after a resource is created by invoking a process on the machine running Terraform (see [here](https://www.terraform.io/docs/provisioners/local-exec.html) for more information). Do note that the use of provisioners is considered to be a possible security vulnerability and therefore recommended as a practice of last resort. This is a tutorial so we'll go with it.

Another thing to bear in mind about provisioners is that by default they run when the resource they're defined in is created, but we can change it to run [before the resource is destroyed](https://www.terraform.io/docs/provisioners/index.html#destroy-time-provisioners). Furthermore, multiple provisioner blocks could be included in the same resource block, and if they are they'll execute in the order they were defined. In our case, the last thing we'd like to do is start the *ssh-agent* service and add the private key to our key chain. When we do this, the only we'd have to do is connect to our instance with `ssh -A ec2-user@ip_address`. Yes, it saves times... try doing all of that manually every single time.

Depending on your Operating System of choice, the commands issued to set the file with user-level read-only permissions vary. In Linux or macOS this is achieved by running `$ chmod 400 key_file.pem` but it's a little more verbose on Windows: `$ icacls ${local.key_file} /inheritancelevel:r /grant:r johndoe:R`. Remember to replace "johndoe" with your username.

```terraform
# ./keys.tf

resource "local_file" "my_key_file" {
  content  = tls_private_key.rsa_key.private_key_pem
  filename = local.key_file

  provisioner "local-exec" {
    command = local.is_windows ? local.powershell : local.bash
  }

  provisioner "local-exec" {
    command = local.is_windows ? local.powershell_ssh : local.bash_ssh
  }
}

locals {
  is_windows = substr(pathexpand("~"), 0, 1) == "/" ? false : true
  key_file   = pathexpand("~/.ssh/sdn_tutorial_key.pem")
}

locals {
  bash           = "chmod 400 ${local.key_file}"
  bash_ssh       = "eval `ssh-agent` ; ssh-add -k ${local.key_file}"
  powershell     = "icacls ${local.key_file} /inheritancelevel:r /grant:r johndoe:R"
  powershell_ssh = "ssh-agent ; ssh-add -k ~/.ssh/sdn_tutorial_key.pem
}
```

There are three (3) new things in this code snippet: `locals {}`, `substr()` and `pathexpand()`.

[Locals](https://www.terraform.io/docs/configuration/locals.html) are like a function's temporary local variable and they are helpful in avoiding repetition of the same values. According to the documentation, they are to be used in moderation and only when a single value or result is used in many places and the value is likely to be changed in the future.

The two other things are Terraform [functions](https://www.terraform.io/docs/configuration/functions.html). These are built-in functions provided by the Terraform language. Note that Terraform does not support user-defined functions. The `substr(string, offset, length)` is a String function that allows us to extract a substring from the start and end index of a string (offset and length). The `pathexpand(path)` is a Filesystem function that takes a path and replaces it with the current user's home directory path. Since the first character of a user's home directory path is different in Unix vs Windows, we can use this to determine if we're on a Unix friendly OS or a Windows OS.

Generate another execution plan with `terraform plan` before proceeding to know we're alright.

## Compute

We're now ready to define our compute instances. First of all, we need to specify an [Amazon Machine Image (AMI)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) because it provides the information required to launch an instance. We'll use one that is free, supported and maintained by AWS: [Amzon Linux 2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html#amazon-linux). We'll use a Terraform [data source](https://www.terraform.io/docs/configuration/data-sources.html) to fetch the ID of the Amazon Linux 2 from the AWS SSM Paremeter store.

A data source allows us to fetch or compute data elsewhere. A data source is typically provided a provider like `hashicorp/aws` ; in this case, we'll use the `aws_ssm_parameter` data source, see [here](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter). To figure out the path of an AMI from the SSM Paremeter Store, read [this](https://aws.amazon.com/blogs/compute/query-for-the-latest-amazon-linux-ami-ids-using-aws-systems-manager-parameter-store/) AWS article.

```terraform
# ./compute.tf

data "aws_ssm_parameter" "linux_latest_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}
```

We can now proceed with our [EC2 instance resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) and insert all of the required (ami and instance type) and optional (key name, subnet id, vpc security group id) arguments.

```terraform
# ./compute.tf

resource "aws_instance" "jump_box" {
  ami           = data.aws_ssm_parameter.linux_latest_ami.value
  instance_type = "t2.micro"
  key_name      = "sdn_tutorial_key"

  subnet_id              = aws_subnet.pub_sub.id
  vpc_security_group_ids = [aws_security_group.general_sg.id, aws_security_group.bastion_sg.id]

  tags = {
    Project = "sdn-tutorial"
  }
}

resource "aws_instance" "app_instance" {
  ami           = data.aws_ssm_parameter.linux_latest_ami.value
  instance_type = "t2.micro"
  key_name      = "sdn_tutorial_key"

  subnet_id              = aws_subnet.prv_sub.id
  vpc_security_group_ids = [aws_security_group.general_sg.id, aws_security_group.app_sg.id]

  tags = {
    Project = "sdn-tutorial"
  }
}
```

## Apply

Let's go ahead and issue a `$ terraform apply` command. This will create an execution plan first, ask for you approval, and then build all of the required infrastructure to match your desired state. Read more about it [here](https://www.terraform.io/docs/commands/apply.html). In case you want to issue implicit approval, use the `-auto-approve` option with the command.

## State Management

There's a lot to say about state management so I'll summarize the single most important thing to know for now: do not commit your `.tfstate` files because they will contain sensitive information like your AWS account number and any other value you used or Terraform used to interact with the AWS API. Here's a [useful site](https://www.toptal.com/developers/gitignore) to know which files should be added to `.gitignore`.

Furthermore, there are two kinds of state: local state and remote state. By default, Terraform stores state locally. When you're working alone that's kind of alright, but when you're working in a team it makes things complicated if not impossible because there's uncertainty in regards to the source of truth. With [remote state](https://www.terraform.io/docs/state/remote.html), Terraform writes state data to a remote data store, which not only means you can share it with your team, but you're not keeping sensitive information in your computer.

There's a lot more to know about Terraform, but that's for another day. For now, inspect the `.tfstate` files that were generated in your working directory to get a sense of the information they contain.

## Destroy

When you're done checking out all your work, go ahead and destroy all of the resources with `$ terraform destroy -auto-approve`. That's the beauty of infrastructure as code: create, update and destroy in a heartbeat.

# Further considerations

There's a ton of stuff we left out due to time and space considerations. We'll use this space to talk about how we can improve our design. The biggest issue I have with this code is in regards to hard-coded values. What if we'd like to use a different availability zone, AMI, key name, instance type, project tag and/or CIDR block? We'll need to change all of those values in every file.

We can certainly avoid that by using [Input Variables](https://www.terraform.io/docs/configuration/variables.html) to have a file containing the variables we'd like to use in a given configuration.

## Variables

Input variables allow us to provide Terraform with the values we need for a given module. In a way, variables are like function arguments. This allows for module customization, without having to alter the code, and makes our module shareable. For instance, if we'd like to customize the availability zone, we can use the following variable:

```terraform
variable "az" {
  description = "Availability Zone"
  type = string
  default = "us-east-1a"
}
```

This will allow us to refer to this variable as `var.az`. When we include the `default` parameter, it makes our variable to be considered optional and uses the default value if a variable is not provided. We can provide variables with the CLI by using the `-var="NAME=VALUE"` option, in a variable definitions file that ends in `.tfvars`, as environment variables, and in a Terraform Cloud Workspace.

For example, to provide the `var.az` file from the CLI we could execute a `plan` OR `apply` command as: `terraform apply -var="az=us-east-1a"`. However, as you may quickly notice, it'll be extremely inconvenient having to do this with a lot of variables. That's where variable definition files come in. We create a file named `testing.tfvars` and in it define our variables (we can name it however we want but it has to end with `.tfvars`).

```terraform
# terraform.tfvars

az            = "us-east-1a"
instance_type = "t2.micro"
key_name      = "sdn_tutorial_key"
```

This will allow us to refactor our `aws_instance` resource to:

```terraform
resource "aws_instance" "jump_box" {
  ami           = data.aws_ssm_parameter.linux_latest_ami.value
  instance_type = var.instance_type
  key_name      = var.key_name
  # ... the rest is ommitted
}
```

Go ahead and refactor the rest of the code as you see fit. Please note that using variables require us to declare them first, as we did above. Typically, they are declared in a `variables.tf` file in a module.

## Outputs

Another thing worth talking about are output values. We have already mentioned them indirectly when referring to exported attributes in the Attributes Reference section of our resources. What's important here is that we can control and define exported values we'd like to save in order to make reference to them in another file.

For example, to connect to our EC2 instances we need the public IP address of the jump box and the private IP address of the application instance. We can get this information by being explicit about [output values](https://www.terraform.io/docs/configuration/outputs.html).

Create a file named `outputs.tf` and in it write the following:

```terraform
output "jump_box_ip" {
    value = aws_instance.jump_box.public_ip
}

output "app_instance_ip" {
    value = aws_instance.app_instance.private_ip
}

output "ssh_key_path" {
  value = local_file.my_key_file.filename
}
```

The above-mentioned output values will be the last thing you see in your terminal after a `terraform apply`. Go ahead and try it.

## Modules

We briefly talked about modules when describing how Terraform loads all of the files in your working directory and that all these files where considered the root module. This is the essence of the idea, but Terraform allows us to take this even further with the use of `module` blocks. If all files from a working directory are loaded into a root module, we can create directories and group infrastructure objects that are related to each other but different from the rest. We can then call other modules by using the `module` keyword.

At the moment, we have a flat structure with all files in one (1) module. We did separate things by function to its own file but we can use the same idea and create a working directory for `./modules/compute` or `./modules/network`. This way our root module can call the compute module.

For example, if we go back to the idea of having a main file called `main.tf`, we could have the following:

```terraform
module "compute" {
  source         = "./modules/compute"
  pub_sub_id     = aws_subnet.pub_sub.id
  bastion_sg_ids = [aws_security_group.general_sg.id, aws_security_group.bastion_sg.id]
  app_sg_ids     = [aws_security_group.general_sg.id, aws_security_group.app_sg.id]
}
```

We'll have to provide the values needed by all of the compute resources in someway, and this might not be the *best* way to do that, but it's enough to get you started. However, doing this would imply creating a `variables.tf` file in the root of the `./modules/compute` directory wherein you'd define all of the required variables mentioned above, except the source (`pub_sub_id`, `bastion_sg_ids` and `app_sg_ids`).

```terraform
# ./modules/compute/variables.tf

variable "pub_sub_id" {
  type = string
}

variable "bastion_sg_ids" {
  type = list
}

variable "app_sg_ids" {
  type = list
}
```

This would also imply a refactor of our `./outputs.tf` because the values declared therein have moved to another location.

```terraform
# ./outputs.tf

output "jump_box_ip" {
  value = module.compute.jump_box_ip
}

output "app_instance_ip" {
  value = module.compute.private_ip
}

output "ssh_key_path" {
  value = local_file.my_key_file.filename
}
```

This also means we need to make sure our compute module is exporting output values, otherwise there'll be nothing to *bubble up*.

```terraform
# ./modules/compute/outputs.tf

output "jump_box_ip" {
    value = aws_instance.jump_box.public_ip
}

output "app_instance_ip" {
    value = aws_instance.app_instance.private_ip
}
```

By the way, why do you think I said *bubble up* when making reference to the use of output values from a nested module by the root module? *Hint: dependency graph*.

# Further reading

There are a ton of people and companies pumping Terraform tools into the ecosystem. There are too many to mention but I think of [Cloude Posse](https://github.com/cloudposse), [Truss](https://github.com/trussworks) and [Gruntwork](https://github.com/gruntwork-io) as some folks you can turn to inspiration. There's something for about everything you can think of in there. Okay, except Terraforming Mars, we're not there yet.

# Ciao

A link to the GitHub repository can be found [here](https://github.com/adriaanbd/tf_aws_sdn), but it does not include any of the refactoring exercises because that's on you to pull off and consider. Plus, it isn't that *big* yet, and a flat module structure works for now.

Feel free to comment, critique, ask questions or anything really.

All the best, and until next time!

