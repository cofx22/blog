Title: Setting up Dokku on Azure with Terraform and Ansible: a Guided Tour
Date: 2019-01-10
Tags: Dokku, Azure, Terraform, Ansible
Canonical-URL: https://www.kabisa.nl/tech/setting-up-dokku-on-azure-with-terraform-and-ansible-a-guided-tour

*This post first appeared on [Kabisa's Tech Blog](https://www.kabisa.nl/tech/).*

This post provides a guided tour of the Terraform configuration and Ansible playbooks in the following repository: [https://github.com/ljpengelen/dokku-on-azure](https://github.com/ljpengelen/dokku-on-azure).

If you follow all the steps described in README.md, you’ll be able to deploy a static front end and a back end defined by any Dockerfile, simply by pushing code to some Git repositories.
The end result is a virtual machine on [Microsoft Azure](https://azure.microsoft.com/) running [Dokku](http://dokku.viewdocs.io/dokku/), an open-source platform as a service.
efore we start the guided tour, let’s start with some why’s.

**Why would you want to do a deployment by pushing to a repository?**
If *you* can deploy an application by pushing to a repository, then so can tools for continuous integration and deployment, such as [Jenkins](https://jenkins.io/).
Even in environments with strict firewall policies, tools like Jenkins should always be able to interact with repositories, without any additional plugins and with little effort.
This makes setting up continuous deployment easy.

**Why use Dokku as a platform as a service?**
Similar functionality can be achieved with [Heroku](https://www.heroku.com/) and [Azure web apps for containers](https://azure.microsoft.com/en-us/services/app-service/containers/).
This type of managed solutions comes with the additional benefit of limited to no maintenance costs.
However, they also come with a considerable price tag if you’re deploying resource-hungry applications.
Running a VM with about 16GB of RAM will cost you around 100 dollars per month, whereas a similar amount of RAM will cost around 500 dollars if you use a managed service.
Clearly, performing maintenance is not free and puts the burden of securing your infrastructure on you.
That could be something you’re very willing to pay for.

**Why use Terraform to manage infrastructure as code?**
Terraform is not the only tool that allows you to manage infrastructure as code.
You could use vendor-specific tools, such as [Azure Resource Manager templates](https://docs.microsoft.com/en-us/azure/templates/) and [AWS CloudFormation](https://aws.amazon.com/cloudformation/) instead, for example.
The benefit of using Terraform is that it is one single tool you can use to manage infrastructure hosted by [many different providers](https://www.terraform.io/docs/providers/index.html).

## Terraform

You can use Terraform to manage infrastructure, such as virtual machines, by means of declarative descriptions of the desired end result.
These descriptions are called configurations.
Terraform keeps track of the current state of the infrastructure and is able to determine which (incremental) changes are required when a configuration changes.
This state can be stored online and shared between developers.

The module [azure_vm](https://github.com/ljpengelen/dokku-on-azure/blob/master/terraform/modules/azure_vm/main.tf) in the [repository accompanying this post](https://github.com/ljpengelen/dokku-on-azure) defines which infrastructure we want to set up on Azure to end up with a publicly accessible virtual machine running Ubuntu.
Part of this module is shown below.

```
variable "admin_username" {}

...

variable "vm_size" {
  default = "Standard_B1S"
}

variable "http_whitelist_ip_ranges" {
  default = ["0.0.0.0/0"]
}

...

data "azurerm_resource_group" "main" {
  name = "${var.resource_group_name}"
}

...

resource "azurerm_public_ip" "main" {
  name = "${var.env}-public-ip"
  location = "${data.azurerm_resource_group.main.location}"
  resource_group_name = "${data.azurerm_resource_group.main.name}"
  public_ip_address_allocation = "static"
  domain_name_label = "${var.domain_name_label_prefix}-${var.env}"
}
```

This module uses a number of [variables](https://www.terraform.io/docs/configuration/variables.html).
These variables can be strings, lists, or maps, where string is the default type.
The variables `admin_username` and `vm_size` have type strings.
It’s possible to specify default values for variables, which are used when no value is declared for the variable at some other point in the configuration.
The variable `http_whitelist_ip_ranges` has a list as default value, from which Terraform is able to imply that this variable has the type list.

For each environment, there’s a configuration file that provides the values for the variables of this module for the given environment.
The file [main.tf](https://github.com/ljpengelen/dokku-on-azure/blob/master/terraform/dev/main.tf), for example, provides value for the development environment.

The module above also contains a [data source](https://www.terraform.io/docs/configuration/data-sources.html), which is used to fetch data about an existing Azure resource group with a given name.
This data source is used to define the location (`location = "${data.azurerm_resource_group.main.location}"`) and resource group name (`resource_group_name = "${data.azurerm_resource_group.main.name}"`) of resources that are defined elsewhere in the configuration.

The most important part of a Terraform configuration are its [resources](https://www.terraform.io/docs/configuration/resources.html).
In the partial example above, a resource defining a [public ip](https://www.terraform.io/docs/providers/azurerm/r/public_ip.html) is used.
Terraform has [documentation](https://www.terraform.io/docs/providers/azurerm/index.html) for each type of Azure resource you’d want to create.
If you look at the [complete module](https://github.com/ljpengelen/dokku-on-azure/blob/master/terraform/modules/azure_vm/main.tf), you’ll see that it declares resources representing a virtual machine, a network security group, a virtual network, and so on.

Although there are multiple ways to [hide secrects in Terraform](https://tosbourn.com/hiding-secrets-terraform/), I’ve chosen to keep things simple and just keep the secrets out of version control entirely.

I’ve chosen to use three separate and independent configurations for the [development](https://github.com/ljpengelen/dokku-on-azure/blob/master/terraform/dev/main.tf), [staging](https://github.com/ljpengelen/dokku-on-azure/blob/master/terraform/staging/main.tf), and [production](https://github.com/ljpengelen/dokku-on-azure/blob/master/terraform/production/main.tf) environments, which all use the module described above.
This is not necessarily the Terraform way of doing things, but it has the benefit of being able to manage all environments independently.
If you upgrade the configuration, you’ll be able to test the effects of that change on one environment, while leaving the others intact.

## Ansible

After you’ve set up your infrastructure with Terraform, you can use Ansible to automate the installation of software on the virtual machines that are part of that infrastructure.
In essence, Ansible is a tool that connects to remote machines via SSH and performs various actions on these machines.
In contrast to similar tools, Ansible doesn’t try to abstract from the operating system running on the remote machine.
For example, this means that when you connect to a remote machine running Ubuntu, you have to upgrade packages using Ansible tasks specific to `apt`, but if you connect to a remote machine running CentOS, you have to upgrade packages using tasks specific to `yum`.

The installation and configuration process that Ansible is supposed to execute is described in the form of playbooks.
A playbook consists of a number of roles and tasks, as shown below.

```
---
- hosts: dokku
  vars:
    dokku_version: v0.14.0
    ports:
      - 80
      - 8080
  remote_user: "{{ admin_username }}"
  roles:
    - print_affected_hosts
    - upgrade_apt_packages
    - secure_server
    - install_dokku
  tasks:
  - name: Install dokku-dockerfile plugin
    become: yes
    command: dokku plugin:install https://github.com/mimischi/dokku-dockerfile.git
    args:
      creates: /var/lib/dokku/plugins/available/dockerfile
```

Each role is a collection of tasks, and each task is an atomic action, often corresponding to the execution of a single command.

The playbook above is quite simple.
It prints the hostname(s) of the machine(s) that Ansible is connecting to, upgrades packages, sets up a firewall, installs Dokku, and installs the [dokku-dockerfile plugin](https://github.com/mimischi/dokku-dockerfile).
At the start of the playbook, a variable representing the Dokku version to install and one representing the list of ports to open are declared.
The playbook also states that Ansible should use the value of the variable `admin_username` as username when connecting to the machine it is configuring via SSH.
This variable is environment specific and defined elsewhere.

Although Ansible provides a [vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) to be able to keep encrypted secrets in version control, I’ve again chosen to keep things simple and keep secrets out of version control entirely.

## Dokku

The Ansible playbook [dokku_apps.yml](https://github.com/ljpengelen/dokku-on-azure/blob/master/ansible/dokku_apps.yml) configures two apps named “front-end” and “back-end”.
Dokku provides a Git repository for each of these apps.
Pushing to one of these repositories will trigger the deployment of the corresponding app.

The [nginx buildpack](https://github.com/dokku/buildpack-nginx) is used to deploy the front end as a static website.
It is triggered by the presence of a file called `.static` in the root of the repository.
To be able to clone the repository for this app before the initial push, this repository is initialized as part of the configuration with Ansible.
This makes the initial deployment the same as all the following ones, which in turn simplifies setting up continuous deployment.

```
- name: Initialize repositories for static apps
  command: dokku git:initialize {{ item.name }}
  args:
    creates: /home/dokku/{{ item.name }}/branches
  when: item.static
  with_items: "{{ apps }}"
```

By default, the nginx buildpack serves files from the root of the repository.
The following command executed by Ansible ensures that nginx uses the dist folder as root instead.

```
- name: Configure nginx for static apps
  command: dokku config:set {{ item.name }} NGINX_ROOT=dist
  when: item.static
  with_items: "{{ apps }}"
```

By default, static apps are exposed on a random port after the first deployment. Specifying a fixed port is also part of the configuration with Ansible.

```
- name: Configure ports for static apps
  command: dokku proxy:ports-add {{ item.name }} http:{{ item.port }}:5000
  when: item.static
  with_items: "{{ apps }}"
```

The back end is deployed by creating a Docker container from a Dockerfile in the corresponding repository.
By default, Dokku looks in the root of this repository for the Dockerfile.
To support monorepos and keep the root of the repository clean, we use the [dokku-dockerfile plugin](https://github.com/mimischi/dokku-dockerfile).
This instructs Dokku to look for the Dockerfile in `dockerfiles/deploy`.

```
tasks:
- name: Configure dokku-dockerfile plugin
  command: dokku dockerfile:set back-end dockerfiles/deploy/Dockerfile
```

## Conclusion

I’ve written this post for anyone in the situation I was in about a year ago.
If you’ve never worked with Azure, Terraform, or Ansible, I hope this post lowers the barrier to get started.
I also hope that this post triggers some discussions about best practises.
If you see any room for improvement or want to share your opinion about this topic, be my guest!
