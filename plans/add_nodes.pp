# Plan: boltello::add_nodes
#
plan boltello::add_nodes(
  TargetSpec $nodes,
  Optional[Boolean] $fresh_install  = false,
  Optional[Boolean] $manage_package = true,
  Optional[Boolean] $migrate_hosts  = false,
  Optional[Boolean] $monolithic     = false,
  Optional[Boolean] $force          = false,
  Optional[Boolean] $clean_certs    = false,
  Optional[TargetSpec] $server      = $monolithic ? {
    true  => get_target('katello'),
    false => undef
  },
  String $boltdir = boltello::get_boltdir()
) {
  $puppet = '/opt/puppetlabs/bin/puppet'

  $katello = get_target('katello')
  $proxies = get_targets('proxies')

  if $force and !$migrate_hosts {
    fail_plan("the option 'force=true' has no affect without 'migrate_hosts=true'")
  }

  $ca_query = run_command('/opt/puppetlabs/bin/puppet config print ca_server',
    get_target($server),
    'locate puppet certificate authority',
  ).first

  $ca_server = $ca_query.value['stdout'] 

  # Agents only
  if get_target($server) in $nodes {
    fail_plan("Remove ${server} from the list of target nodes")
  }

  if get_target($ca_server) in $nodes {
    fail_plan("Remove ${ca_server} from the list of target nodes")
  }

  $autosign_query = run_command('/opt/puppetlabs/bin/puppet config print autosign --section master',
    get_target($ca_server),
    'discover autosign features',
    _catch_errors => true
  ).first

  $autosign = $autosign_query.value['stdout'].strip() ? {
    /(autosign|conf)/ => 'conf',
    /true/            => 'simple',
    default           => 'off'
  }

  get_targets($nodes).each |TargetSpec $node| {

    # Remove agent and release packages
    if $fresh_install and !$manage_package {
      fail_plan("use 'manage_package=true' and 'fresh_install=true' to perform a fresh installation")
    } elsif $fresh_install and $manage_package {
      $puppet_package_query = run_command('[ $(which rpm 2>/dev/null) ] && rpm -q puppet-agent || $(apt list | grep puppet-agent)', 
        $node,
        'check puppet rpm',
        _catch_errors => true
      )

      if $puppet_package_query.ok {
        run_command('[ $(which yum 2>/dev/null) ] && yum -y remove puppet-agent || apt-get -y remove puppet-agent', 
          $node, 
          'remove agent package'
        )

        run_command('[ $(which yum 2>/dev/null) ] && yum -y remove puppet*-release || apt-get -y remove puppet*-release', 
          $node, 
          'remove release package'
        )
      } else {
        warning("Advisory: no puppet-agent package found on ${node.name}")
      }
    }

    # Install puppet-agent package
    if $manage_package {
      run_plan('boltello::install_puppet',
        $node,
        boltdir       => $boltdir,
        server        => $server,
        manage_config => true
      )
    }

    $puppet_ssl_query = run_command('/opt/puppetlabs/bin/puppet config print ssldir',
      $node,
      'get ssldir location',
      _run_as       => 'root',
    ).first

    $ssl_dir = $puppet_ssl_query.value['stdout'].strip()

    $private_key_exists = run_command("/bin/test -f ${ssl_dir}/private_keys/${node.name}.pem",
      $node,
      'check for existing private_key',
      _catch_errors => true
    )

    if $clean_certs {
      run_command("${puppet}server ca clean --certname ${node.name} || :",
        get_target($ca_server),
        "clean certitificate for node ${node.name} on puppetmaster",
        _catch_errors => true
      )
    }

    if $migrate_hosts {
      run_command("${puppet} resource service puppet ensure=stopped",
        $node,
        'stop agent service'
      )

      $puppet_server_query = run_command('/opt/puppetlabs/bin/puppet config print server',
        $node,
        'get server identity',
        _run_as       => 'root',
      ).first

      $configured_server = $puppet_server_query.value['stdout'].strip()

      if $configured_server != get_target($server).name {
        run_command("${puppet} config set server ${server} --section main",
          $node,
          "set server identity: ${server}"
        )
      }

      if $private_key_exists.ok and $force {
        run_command("/bin/rm -fr ${ssl_dir}", 
          $node, 
          'force remove ssl dir'
        )
      } 
    }

    if $private_key_exists.ok and !$migrate_hosts {
      fail_plan("Private key found on ${node.name}. Use 'migrate_hosts=true', or remove manually")
    }

    case $autosign { 
      'off': {
        warning("Advisory: autosign not enabled on ${ca_server}, you must sign the certificate manually")
      }
      'conf': { 
         warning("Advisory: autosign access file found on ${ca_server}; ensure rules match or sign the certificate manually")
       }
       default: {
       }
    }

    # Run puppet agent
    $run_puppet = run_command("${puppet} agent -t --server ${server} --waitforcert 5",
      $node,
      'connect agent to new puppetmaster'
    )

    if !$run_puppet.ok {
      warning("Advisory: puppet agent run failed on ${node.name}")
      warning("  try 'fresh_install=true' or 'force=true'")
      warning("  use 'clean_certs=true' if there's a certificate mismatch")

    } else {
      $migrate_or_join_new = $migrate_hosts ? {
        true    => "migrated",
        default => "joined"
      }

      warning("Advisory: successfully ${migrate_or_join_new} node to ${server}")

      if $migrate_hosts {
        run_command("${puppet} resource service puppet ensure=running",
          $nodes,
          'ensure agent service is running'
        )
      }

      # Ensure foreman smart proxy public key
      $enable_remote_execution = lookup('boltello::enable_remote_execution')
      $ssl_port = lookup('boltello::foreman_proxy_ssl_port')

      if $enable_remote_execution {
        $public_key_query = run_command("/bin/curl -k https://localhost:${ssl_port}/ssh/pubkey",
          $server,
          'fetch public key from proxy server',
          _catch_errors => true
        )

        $public_key = $public_key_query[0].value['stdout'].strip()

        if $public_key_query.ok {
          run_command("[[ $(/bin/grep 'foreman-proxy@${get_target($server).name}' /root/.ssh/authorized_keys) ]] || echo '${public_key}' >> /root/.ssh/authorized_keys",
            $node,
            'add proxy public key to agent'
          )
        }
      }
    }
  }
}
