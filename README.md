# boltello

#### Table of Contents

  1. [Description](#description)
     * [Roles](#roles)
     * [Features](#features)
  2. [Setup - The basics of getting started with boltello](#setup)
     * [What boltello affects](#what-boltello-affects)
     * [Quickstart](#quickstart)
     * [Setup requirements](#setup-requirements)
     * [Pre-flight](#pre-flight)
     * [Bolt workflow](#bolt-workflow)
     * [Post-flight](#post-flight)
  3. [Usage - Configuration options and additional functionality](#usage)
  4. [Limitations - OS compatibility, etc.](#limitations)
  5. [Development - Guide for contributing to the module](#development)

## Description

Install [Katello](https://www.theforeman.org/plugins/katello/) and [capsule servers](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.3/html/installation_guide/what_satellite_server_and_capsule_server_do) with [Puppet Bolt](https://puppet.com/products/bolt).  
> "Katello is a systems life cycle management plugin to Foreman. Katello allows you to manage thousands of machines with one click. Katello can pull content from remote repositories into isolated environments, and make subscriptions management a breeze." 

> "Foreman (also known as The Foreman) is an open source complete life cycle systems management tool for provisioning, configuring and monitoring of physical and virtual servers. Foreman has deep integration to configuration management software, with Ansible, Puppet, Chef, Salt and other solutions through plugins, which allows users to automate repetitive tasks, deploy applications, and manage change to deployed servers."

> "The Smart Proxy server is a Katello component that provides federated services to discover, provision, control, and configure hosts. Each Katello server includes a Default Smart Proxy, and you may deploy additional Smart Proxies to remote data centers."

> "Bolt's agentless multi-platform solution allows you to get started without the prerequisites of an agent or any Puppet knowledge. 
Choose your operating system, follow the install link and run the listed Bolt command via your command line interface."

**References**: [Satellite](https://www.redhat.com/en/technologies/management/satellite), [Puppet](https://puppet.com/products/how-puppet-works)

This Bolt project replaces the Katello installer -- or the [foreman-installer](https://github.com/theforeman/foreman-installer) -- with Puppet Bolt. Configuration data is derived from foreman-installer [answer files](https://github.com/theforeman/foreman-installer/blob/develop/config/) and stored in boltello's [Hiera backend](data) where it is shared between Puppet and Bolt. 

Boltello was created out of a desire to produce a completely Hiera-driven, enterprisey-installation of open source Puppet, replete with all of the bells and whistles preconfigured; i.e, the Foreman GUI and ENC, Katello packaging management, Hiera, r10k and Foreman REX integration. 

## Roles

Boltello's concept of "roles" is more akin to a "profile"; e.g., a data collection which defines significant features of a given object or entity. There are three pre-defined roles, or profiles, in boltello and the provision to add custom, user-defined roles is built-in:

| Role/Profile | Description |
| -------- | -------- | 
| \* *katello* | The boltello Master of masters or solitary CA  |
| \* *proxy* | The boltello Puppet compile master; Puppet certificate proxy and companion role to the 'katello' role |
| *capsule* | Vanilla Capsule server; Puppet CA and companion role to the 'katello' role |

  \* Default profile, implements a single Puppet CA
  
A vanilla Katello installation configures each Puppet compile master, or Capsule server, as a Puppet Certificate Authority. In contrast, Boltello scales Katello infrastructure by [centralizing the (Puppet) certificate authority](https://puppet.com/docs/puppetserver/6.0/scaling_puppet_server.html#centralizing-the-certificate-authority) on the Katello server and configuring capsule servers to [proxy certificate requests](https://bugzilla.redhat.com/show_bug.cgi?id=1233302) to the designated Katello server; i.e. the [Puppet master CA](https://puppet.com/docs/pe/2018.1/pe_architecture_overview.html#pe-architecture-the-master-of-masters-mom). 

Boltello provides the three pre-defined profiles as a means to diversify the topology of your Katello infrastructure. See how to load non-default profiles below.

**NOTE**: While the Apache web server is used ubiquitously throughout the Katello stack, Boltello uses Nginx to proxy Puppet requests. It's a long and complex tale, spanning multiple stories and tickets; however, it can basically be summarized thusly: Puppet, Apache, Nginx and OpenSSL each handle client headers differently; yet, the Nginx configuration employed by Boltello, magically, "[just works](data/roles/proxy.yaml#L94)". 

For further reading:
  * [Puppetserver Support for X-Client-DN and X-Client-Verify Headers](https://tickets.puppetlabs.com/browse/SERVER-18)
  * [Cannot decode OpenSSL-formatted X-Client-DN header](https://tickets.puppetlabs.com/browse/SERVER-213)
  * [Cannot decode Apache-formatted X-Client-Cert header](https://tickets.puppetlabs.com/browse/SERVER-217)
  * [Puppetserver External SSL termination](https://puppet.com/docs/puppetserver/6.12.2/external_ssl_termination.html)
  * [Puppetserver request_handler_core.clj](https://github.com/puppetlabs/puppetserver/blob/6.x/src/clj/puppetlabs/services/request_handler/request_handler_core.clj)

If you discover a working Apache vhost definition that handles SSL client headers better than Nginx, please post the solution [here](https://github.com/superfantasticawesome/boltello/issues). 

## Features

  * In place upgrades of Katello/Foreman
  * Add/Migrate agents from one puppetmaster to another with the 'boltello::add_nodes' plan
  * Manage cross-datacenter Foreman/Puppet federation with a single Puppet CA
  * Manage catalog master installations remotely, from the Katello master server, using Puppet Bolt
  * Proxy Puppet agent certificate requests through catalog masters to the Puppet CA using nginx
  * Install a Puppet agent and bind it to its respective catalog master with a single command
    ```bash
    curl -k https://fqdn-of-local-master:8140/install | bash
    ```
  * Manage Foreman's ignored_environments feature with the 'boltello::ignored_environments' Array 
     * Where environments are the branches of your [control repo](https://github.com/puppetlabs/control-repo) which you don't wish to be visible to Foreman:
       ```bash
       'boltello::ignored_environments':
         - 'common'
       ```
  * Manage the Yum [versionlock plugin](https://linux.die.net/man/1/yum-versionlock) with the 'boltello::versionlock_packages' Hash
    ```bash
    'boltello::versionlock_packages':
      'puppetserver': '6.4.0'
      'fuafup': '13.9.4'
      'susfu': '1.7.1'
      
    ```
  * Foreman Remote Execution, r10k and Hiera integration
  * Foreman Hammer client integration

__A note regarding Hiera lookup()__

  * Bolt's Hiera implementation is explicity disallowed from interpolating fact values in Hiera lookups
  * This means that any key with an interpolation token in its value is REMOVED from search returns by Bolt
  * To solve around this limitation, boltello swaps lookup() with the loadyaml() function to access the __raw__ YAML in data/plans/common.yaml 
  * Additionally, common.yaml is referenced thoughout the hierarchy for normal Puppet lookups in order to avoid data duplication

__Generating a CSR__

  * Boltello loads the "subject_alt_names" array as raw YAML and combines the result of a regex on the node's "certname", with a split on each element of the array containing an interpolation token; e.g., '%' (see above)
  * The sole assumption is that any interpolation token used in the "subject_alt_names" array references a "domain" fact; e.g., %{facts.networking.domain}
  * Dirty interpolation via loadyaml() is provided as a means to localize DNS records per datacenter/location; no other fact values are manipulated as described above
  * Also see the "boltello::katello_alt_names" array which contains cnames for the katello server/puppet master CA
  * Be careful editing any metadata outside of data/plans/common.yaml
  * See hiera.yaml

__Certificate Management__

  * Katello comes with a suite of [certificate management](https://theforeman.org/plugins/katello/nightly/advanced/certificates.html) tools
  * Katello/Capsule server certificates are generated with the [katello/certs](https://forge.puppet.com/katello/certs) and [puppet/trusted_ca](https://forge.puppet.com/puppet/trusted_ca) modules
  * Puppet certificates are generated via a Bolt task which adds custom subject alternative names to the CSR 
  * Once certificates are generated via Puppet module and task, they're shipped to their respective host for deployment using Bolt's 'upload_file' method
  * Use Katello certificate tools for managing certificates after installtion and initial configuration

## Setup

### What boltello affects
Package/Feature | Katello | Catalog/Proxy| Agent
----- | :------: | :-------: | :-----:
puppet-agent | ✓ | ✓ | ✓ |
puppetserver | ✓ | ✓ | |
CA | ✓ | | |
hiera | ✓ | ✓ | |
r10k | ✓ | ✓ | |
foreman | ✓ | | |
foreman-proxy | ✓ | ✓ | |
pulp/candlepin/qpid | ✓ | ✓ | |
git | ✓ | ✓ | |
httpd | ✓ | ✓ | |
nginx | | ✓ | |
postgresql | ✓ | | |

### Quickstart
  ```bash
  ssh-keygen -t rsa -b 4096 -N '' -C 'puppet-bolt' -f /root/.ssh/bolt_id_rsa
  cat ~/.ssh/bolt_id_rsa.pub >> /home/centos/.ssh/authorized_keys
  ### Distribute your public key if necessary ###
  rpm -Uvh https://yum.puppet.com/puppet6/puppet6-release-el-7.noarch.rpm
  yum -y install puppet-bolt
  yum -y install git
  git clone https://github.com/superfantasticawesome/boltello.git 
  cd ~/boltello
  export PATH="/opt/puppetlabs/bin:$PATH"
  bolt puppetfile install
  bolt plan run boltello::build_katello
  ```

### Setup Requirements

  * Port connectivity - [see chart](#port-requirements)
  * Install and configure Puppet Bolt
  * Ensure SSH public-key authentication across all nodes
  * Clone this bolt project
  * Edit the Hiera data to match your environment
  * Source the Puppet module dependencies
  * Exec the Bolt orchestration plans

### Pre-flight

The following steps are to be completed on the Katello server

  1. Install Bolt:
     ```bash
     rpm -Uvh https://yum.puppet.com/puppet6/puppet6-release-el-7.noarch.rpm
     yum -y install puppet-bolt
     ```
  2. Install Git
     ```bash
     yum -y install git
     ```
  3. From the root user's $home directory on the Katello server, clone the project; e.g., /root/boltello
     ```bash
     cd ~/
     git clone https://github.com/superfantasticawesome/boltello.git
     ```
  4. Generate/copy the private/public key pair
     * The public key needs to be distributed to all hosts.

### Bolt workflow

The following steps are to be completed on the Katello server

  1. Edit the [inventory.yaml](inventory.yaml) file and add the katello server's hostname to the katello group's nodes array. Also be sure to add the proxy server/s to the proxy group's node array:
     ```bash
     vi ~/boltello/inventory.yaml
     ```
  2. Add the katello server's hostname and proxy server hostnames to the [common.yaml](data/plans/common.yaml) file. The keys to look for are:
     ```bash
     'boltello::katello_server'
     'boltello::katello_proxies'
     ```
       * Leave the '%{trusted.certname}' entry unedited in the proxy server array.
       * Update the usernames/passwords for your deployment.
       * Data in common.yaml is distributed throughout the [hierarchy](data) via interpolation functions.
       * Optionally, edit the r10k remote setting in [common.yaml](data/plans/common.yaml):
           ```bash
           'boltello::r10k_remote': 'https://github.com/puppetlabs/control-repo'
           ```
  3. Next, use Bolt to sync the dependency modules:
     ```bash
     cd ~/boltello
     bolt puppetfile install
     ```
  4. Run the __*boltello::build_katello*__ plan:
     ```bash
     bolt plan run boltello::build_katello 
     ```
     The above plan builds the katello server and generates certificates for each proxy server found in the inventory file.
     For a monolithic build of katello; e.g., no proxies, run the command below and skip step 5:
     ```bash
     bolt plan run boltello::build_katello monolithic=true
     ```
     __Primary command line options__
       ```bash
       agent_only   # installs puppet and exits plan
       katello_prep # installs puppet and katello packages only; use 'force=true' to ensure all packages
       monolithic   # installs puppet and katello packages, sets facts and runs puppet apply
       ```

       Primary options represent runtime stages and are mutually exclusive

       __Other options__
       ```bash
       force         # ensures installation even if desired version is achieved
       role_override # loads a user-specified YAML file from data/roles
       puppet_certs  # enable/disable puppet certificate generation on the master; enabled by default
       ```
     Role override example:
       ```bash
       bolt plan run boltello::build_katello role_override='custom_role'
       ```
       * Loads 'data/roles/custom_role.yaml' 
       (file does not exist; would override ALL values in data/roles/katello.yaml)
       
     When deploying Katello server with a companion 'capsule' role, you must turn off puppet certificate generation on the command line:
       ```bash
       bolt plan run boltello::build_katello puppet_certs=false
       ```
       * Loads the default 'data/roles/katello.yaml'file 
       * Turns off Puppet certificate generation 

  5. Run the __*boltello::build_proxies*__ plan:
     ```bash
     bolt plan run boltello::build_proxies
     ``` 
       __Options__
       ```bash
       force         # ensures installation even if desired version is achieved
       katello_prep  # ensures katello packaging; must use with 'force=true' to ensure all packages
       role_override # loads a user-specified YAML file from data/roles
       ```
     Role override example:
       ```bash
       bolt plan run boltello::build_proxies role_override='capsule'
       ```
       * Loads 'data/roles/capsule.yaml'
       (completely overrides data in data/roles/proxy.yaml)
       * Must be accompanied with:
       ```bash
       bolt plan run boltello::build_katello puppet_certs=false
       ```
     This plan reads in targets from the inventory. See below for adding new proxy servers.

  __One shot deployment__
  
  1. Build full default infrastructure:
       ```bash
       agents=ip-172-31-72-91.ec2.internal,ip-172-31-72-121.ec2.internal
       proxy=ip-172-31-70-200.ec2.internal

       bolt plan run boltello::build_katello && \
       bolt plan run boltello::build_proxies && \
       bolt plan run boltello::add_nodes --targets $agents server=$proxy
       ```
  2. Build full infrastructure with a vanilla capsule server:
       ```bash
       agents=ip-172-31-72-91.ec2.internal,ip-172-31-72-121.ec2.internal
       proxy=ip-172-31-70-200.ec2.internal

       bolt plan run boltello::build_katello puppet_certs=false && \
       bolt plan run boltello::build_proxies role_override='capsule' && \
       bolt plan run boltello::add_nodes --targets $agents server=$proxy
       ```
  3. Build monolithic infrastructure:
       ```bash
       agents=ip-172-31-72-91.ec2.internal
       katello=ip-172-31-70-199.ec2.internal

       bolt plan run boltello::build_katello monolithic=true && \
       bolt plan run boltello::add_nodes --targets $agents server=$katello
       ```

### Post-flight

  1. Ensure hosts and proxies are added to the __correct__ [locations](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.6/html/content_management_guide/managing_locations) and [organizations](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.6/html/content_management_guide/managing_organizations). Proxies __must__ be disambiguated by location. This [Hammer CLI guide](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.6/html-single/hammer_cli_guide/index) may be helpful getting started with Hammer. Also review the [Hammer commands](https://access.redhat.com/documentation/en-us/red_hat_satellite/6.6/html/hammer_cli_guide/chap-cli_guide-organizations_locations_repositories) for managing these configurations. 
  2. Add [katello content](https://www.theforeman.org/plugins/katello/nightly/user_guide/content_hosts/index.html) and publish it.
  3. Add agents to Katello
     * Run the 'boltello::add_nodes' plan:
     
       With proxies:
       ```bash
       targets='agent1.internal,agent2.internal,agent3.internal'
       bolt plan run boltello::add_nodes --targets $targets server=proxy1.internal
       ```
       Monolithic:
       ```bash
       targets='agent1.internal,agent2.internal,agent3.internal'
       bolt plan run boltello::add_nodes --targets $targets monolithic=true
       ```
       Migrating from an existing Puppet master:
       ```bash
       targets='agent1.internal,agent2.internal,agent3.internal'
       bolt plan run boltello::add_nodes --targets $targets migrate_hosts=true manage_package=false force=true server=proxy1.internal 
       ```
       __Other command line options__

       **fresh_install** removes existing packages; **force** removes the certificate directory, without creating a backup; **clean_certs** will force remove a certificate on the katello CA:
       ```bash
       targets='agent1.internal,agent2.internal,agent3.internal'
       bolt plan run boltello::add_nodes --targets $targets \
         migrate_hosts=true \
         fresh_install=true \
         clean_certs=true \
         force=true \
         server=proxy1.internal
       ```
     * Optionally, the following command, executed on a node intended to be a puppet agent, will install the puppet agent package and bind the agent to its respective catalog master/capsule server:
       ```bash
       curl -k https://<fqdn-of-capsule>:8140/install | bash
       ```
       This command can be included in a bootstrap script, executed during host provisioning workflows. 
       
       __Note__: The 'boltello::enable_remote_agent_install' is set to *true* by default; please consider any security implications as *autosign* is enabled by default on the katello CA.
     
  4. Scaling boltello with additional proxies (monolithic or with proxies):
     * Ensure BOTH new proxy/proxies and existing proxies are present in inventory.yaml **and** data/plans/common.yaml
     * Run the 'boltello::build_katello' plan to whitelist the new proxies on the katello server
     * Ensure the 'boltello::build_katello' plan does not include the 'monolithic=true' argument when run
     * Run the 'boltello::build_proxies' plan with the new proxies set as the target list:
       ```bash
       proxies='proxy2.internal,proxy3.internal'
       bolt plan run boltello::build_katello
       bolt plan run boltello::build_proxies --targets $proxies
       ```

  5. Upgrade Katello and Foreman in place:
     * Take a snapshot and/or use [foreman-maintain](https://theforeman.org/plugins/foreman_maintain/) to backup and protect your data.
     * Upgrades must be performed incrementally.
     * Downgrade is not possible.
     * Run the 'boltello::katello_upgrade' plan as shown in the example below.
     * Assuming the current Katello version is **3.12** and you want to upgrade to **3.14**, the updrade steps would be:
     
       With proxies:
       ```bash
       targets='katello.internal,proxy1.internal,proxy2.internal'
       bolt plan run boltello::katello_upgrade --targets $targets katello_version=3.13 foreman_version=1.23
       bolt plan run boltello::katello_upgrade --targets $targets katello_version=3.14 foreman_version=1.24
       ```

       Monolithic:
       ```bash
       bolt plan run boltello::katello_upgrade katello_version=3.13 foreman_version=1.23 monolithic=true
       bolt plan run boltello::katello_upgrade katello_version=3.14 foreman_version=1.24 monolithic=true
       ```

     * The plan is idempotent and may need to be run more than once. To re-run the plan against a node, use the "force" switch:
       ```bash
       bolt plan run boltello::katello_upgrade --target proxy3.internal katello_version=3.13 foreman_version=1.23 force=true
       ```

     * Database operations are performed each run until the installed katello version matches the command line version.
     * Optionally, use 'maintain_database=true' to include database operations each time the plan is executed.
     * Database options:

       ```bash
       maintain_database   # default value false: perform database operations each run 
       manage_candlepin    # default value true: updates the candlepin database
       manage_pulp         # default value true: updates the pulp database
       optimize_database   # default value false: reclaims database storage after migration 
       delete_auditrecords # default value false: delete audit records older than $days_audit days
       delete_reports      # default value false: delete reports older than $days_reports days
       days_audit          # default value 10
       days_reports        # default value 2
       rails_env           # default value production
       ```

       Example:
       ```bash
       bolt plan run boltello::katello_upgrade \
         katello_version=3.14 \
         foreman_version=1.24 \
         monolithic=true \
         force=true \
         maintain_database=true \
         optimize_database=true \
         delete_auditrecords=true \
         delete_reports=true
       ```

     * The 'optimize_database' option uses a selector to locate the database-appropriate command by sniffing the database adapter in /etc/foreman/database.yml. 
     * The 'boltello::katello_upgrade' plan runs two health checks:
         * check the status of katello services 
         * check for active katello tasks 

       If the service check fails, the plan attempts to start katello services. If the active tasks check fails, the plan will exit with an error message. If a failure condition exists, cancel the tasks in katello and re-run the plan. You can also try deleting failed/paused tasks in postgresql:
       ```bash
       su - postgres
       psql foreman
       delete from foreman_tasks_tasks where id in(select id from foreman_tasks_tasks where state = 'paused' and result = 'error');
       delete from foreman_tasks_tasks where id in(select id from foreman_tasks_tasks where state = 'stopped' and result = 'error');
       \q
       ```
     * Once all katello infrastructure is upgraded, update the version metadata in hiera and re-run the 'boltello::build_katello' and 'boltello::build_proxies' plans with "force=true" to ensure fully converged infrastructure.
     * Reboot nodes if necessary; i.e., changes in SELinux policies, etc.

## Usage

  See the [Katello documentation](https://www.theforeman.org/plugins/katello/).
  Also be sure to review the included per-role [Hiera data](data).

## Port Requirements

Port | Protocol | Service| Purpose
----- | :------: | :-------: | :-----:
80 | TCP | HTTP | Anaconda, yum, Katello certificates, templates, downloading iPXE firmware |
443 | TCP | HTTPS | Subscription Management, yum, Telemetry Services, Foreman dashboard |
5467 | TCP | AMQP | Katello Agent communication with Qpid dispatch router|
8140 | TCP | HTTPS | Puppet agent/Puppet master communication |
8443 | TCP | HTTPS | Smart Proxy communication |
9090 | TCP | HTTPS | Smart Proxy communication |

## Reference

  [Katello Documentation](https://theforeman.org/plugins/katello/nightly/index.html)

## Limitations

  Centos/7 only.

## Development

  Fork, branch and send me a pull request.

## Release Notes/Contributors/Etc.

  Gerard Ryan
  * email: hello@superfantasticawesome.com
  * linkedin: https://www.linkedin.com/in/superfantasticawesome/
