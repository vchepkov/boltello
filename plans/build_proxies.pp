# == Plan boltello::build_proxies
#
plan boltello::build_proxies(
  TargetSpec $nodes               = get_targets('proxies'),
  String[1] $boltdir              = boltello::get_boltdir(),
  String[1] $modulepath           = "$boltdir/modules",
  String[1] $hiera_config         = "$boltdir/hiera.yaml",
  Boolean $katello_prep           = false,
  Boolean $force                  = false,
  Optional[Boolean] $apply_noop   = false,
  Optional[String] $role_override = undef,
) {
  # Proxies only
  $katello_server = get_target('katello')

  $enable_remote_execution = lookup('boltello::enable_remote_execution')

  if $katello_server in $nodes {
    fail_plan("Remove ${katello_server} from the list of target nodes")
  }

  $certs_dir = "${boltdir}/modules/boltello_builder/files/certs"
  $puppet_resource = '/opt/puppetlabs/bin/puppet resource service'

  get_targets($nodes).each |TargetSpec $node| {
    $certs_zip = "${node.name}-certs.tar.gz"
    $certs_tar = "${node.name}-certs.tar"

    # Check installed version
    $check_version = run_plan('boltello::check_version', 
      nodes  => $node, 
      force  => $force,
      caller => 'plan',
    )

    # Shift to next node if katello is installed and force not enabled
    if $check_version { next() }

    # Install and configure puppet agent
    run_plan('boltello::install_puppet', 
      nodes   => $node, 
      boltdir => $boltdir, 
    ) 

    $boltello_facts_query = run_command("/opt/puppetlabs/bin/facter boltello_role",
      $node,
      'check for existing boltello_role',
      _catch_errors => true
    )

    $existing_boltello_role = $boltello_facts_query.first.value['stdout'].strip()
    
    $boltello_role = $role_override.empty() ? { 
      true    => 'proxy',
      default => file::exists("${boltdir}/data/roles/${role_override}.yaml") ? {
        true  => $role_override,
        false => 'proxy'
      }
    }

    $puppet_query = run_command('/opt/puppetlabs/bin/puppet config print ssldir',
      $node,
      'retrieve ssldir location',
      _run_as       => 'root',
      _catch_errors => true,
    )

    $ssl_dir = $puppet_query.first.value['stdout'].strip()

    $ssl_directory_exists = run_command("/bin/test -d ${ssl_dir}",
      $node,
      'check for existing ssl directory',
      _catch_errors => true
    )

    if $ssl_directory_exists.ok {
      $change_role = (($existing_boltello_role != '' and $existing_boltello_role == 'proxy' and $boltello_role != 'proxy')
                       or ($existing_boltello_role != '' and $existing_boltello_role != 'proxy' and $boltello_role == 'proxy'))

      if $change_role {
        err("Critical: role change detected on ${node.name}")
        fail_plan("deploy a new server rather than changing an existing role")  
      }
    }

    # Ensure boltello_role fact
    run_task('boltello::boltello_role', 
      $node, 
      "ensure fact boltello_role => ${boltello_role}",
      boltello_role => "${boltello_role}",
    ) 

    $check_directory = run_command('/bin/test -d /root/boltello',
      $node,
      'check for boltello directory',
      _run_as       => 'root',
      _catch_errors => true,
    )

    if $check_directory.ok and $force {
      run_command('/bin/rm -fr /root/boltello',
        $node,
        'check for boltello directory',
        _run_as => 'root',
      )
    }

    if !$check_directory.ok or $force {
      upload_file("${boltdir}/modules/boltello_builder/files/boltello", "/root/boltello", 
        $node, 
        _description => 'upload boltello directory',
        _run_as      => 'root',
      )
    }

    # Copy the puppet certs tarball to the proxies
    if $boltello_role == 'proxy' {
      $check_private_key = run_command("/bin/test -f ${ssl_dir}/private_keys/${node.name}.pem",
        $node,
        'check for private key',
        _run_as       => 'root',
        _catch_errors => true,
      )

      if !$check_private_key.ok {
        run_command("${puppet_resource} puppetserver ensure=stopped", 
          $node, 
          'stop puppetserver service',
          _run_as => 'root',
        )

        run_command("${puppet_resource} puppet ensure=stopped", 
          $node, 
          'stop puppet agent service',
          _run_as => 'root',
        )

        upload_file("${certs_dir}/${certs_zip}", "/tmp/${certs_zip}", 
          $node, 
          _description => 'upload certificate archive',
          _run_as      => 'root',
        )

        run_command("tar -xzf /tmp/${certs_zip} -C /", 
          $node, 
          'extract certificate archive', 
          _run_as => 'root',
        )

        run_command("${puppet_resource} puppet ensure=running", 
          $node, 
          'start puppet agent service',
          _run_as => 'root',
        )
      }
    }

    # Prep node with katello packages
    run_plan('boltello::katello_prep', 
      nodes => $node,
      force => ($katello_prep and $force)
    )

    # Sync puppet modules on the proxies with bolt
    run_task('boltello::puppetfile_install', 
      $node, 
      'run bolt puppetfile install', 
      boltdir => $boltdir
    )

    # Lock packages
    run_plan('boltello::versionlock',
      nodes       => $nodes,
      lock_status => 'locked',
    )

    if !$katello_prep {
      # Configure foreman-proxy user, facts, directories, keys
      run_plan('boltello::foreman_proxy',
        $node,
        _catch_errors => true
      )

      # Copy the katello certs tarball to the proxies
      upload_file("${boltdir}/modules/boltello_builder/files/certs/${certs_tar}", "/root/${certs_tar}", 
        $node,
        _description => 'upload puppet certificates archive',
        _run_as      => 'root',
      )

      run_command("/bin/yum -y localinstall https://${katello_server.name}/pub/katello-ca-consumer-latest.noarch.rpm",
        $node,
        'ensure katello-ca-consumer-latest',
        _catch_errors => true
      )

      # Run puppet
      $run_puppet = run_plan('boltello::run_puppet', 
        nodes        => $node, 
        hiera_config => $hiera_config, 
        modulepath   => $modulepath,
        apply_noop   => $apply_noop,
      )

      if $run_puppet {
        warning("Advisory: katello ${boltello_role} configured on ${node.name}")
      } else {
        err("Critical: katello ${boltello_role} configuration failed")
      }

    } else {
      warning("Advisory: katello packages ensured on ${node.name}")
    }
  }
}
