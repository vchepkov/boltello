# == Plan boltello::build_proxies
#
plan boltello::build_proxies(
  TargetSpec $nodes        = get_targets('proxies'),
  String[1] $boltdir       = boltello::get_boltdir(),
  String[1] $modulepath    = "$boltdir/modules",
  String[1] $hiera_config  = "$boltdir/hiera.yaml",
  Boolean $katello_prep    = false,
  Optional[Boolean] $force = false,
) {
  # Proxies only
  $katello = get_target('katello')

  if $katello in $nodes {
    fail_plan("Remove ${katello} from the list of target nodes")
  }

  $certs_dir = "${boltdir}/modules/boltello_builder/files/certs"
  $puppet_resource = '/opt/puppetlabs/bin/puppet resource service'

  get_targets($nodes).each |TargetSpec $node| {

    # Check installed version
    $katello_installed = run_plan('boltello::check_version', 
      nodes  => $node, 
      force  => $force,
      caller => 'plan',
    )

    # Shift to next node if katello is installed and force not enabled
    if $katello_installed { next() }

    # Install and configure puppet agent
    run_plan('boltello::install_puppet', 
      nodes   => $node, 
      boltdir => $boltdir, 
    ) 

    $puppet_query = run_command('/opt/puppetlabs/bin/puppet config print ssldir',
      $node,
      'retrieve ssldir location',
      _run_as       => 'root',
      _catch_errors => true,
    ).first

    $ssl_dir = $puppet_query.value['stdout'].strip()

    # Ensure boltello_role fact
    run_task('boltello::boltello_role', 
      $node, 
      'ensure fact boltello_role => proxy', 
      boltello_role => 'proxy',
    ) 

    $check_directory = run_command('/bin/test -d /root/boltello 2>/dev/null >&1',
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

    # Copy the certs tarball to the proxies
    $cert_archive = "${node.name}-certs.tar.gz"
    $certs_tar = "${node.name}-certs.tar"
    
    upload_file("${boltdir}/modules/boltello_builder/files/certs/${certs_tar}", "/root/${certs_tar}", 
      $node,
      _description => 'upload certificates archive',
      _run_as      => 'root',
    )

    $check_private_key = run_command("/bin/test -f /etc/puppetlabs/puppet/ssl/private_keys/${node.name}.pem",
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

      upload_file("${certs_dir}/${cert_archive}", "/tmp/${cert_archive}", 
        $node, 
        _description => 'upload certificate archive',
        _run_as      => 'root',
      )

      run_command("tar -xzf /tmp/${cert_archive} -C /", 
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

    # Sync puppet modules on the proxies with bolt
    if !$katello_prep { 
      run_task('boltello::puppetfile_install', 
        $node, 
        'run bolt puppetfile install', 
        boltdir => $boltdir
      )
    }

    # Prep node with katello packages
    run_plan('boltello::katello_prep', 
      nodes => $node,
      force => ($katello_prep and $force)
    )

    # Run puppet
    if !$katello_prep { 
      run_plan('boltello::run_puppet', 
        nodes        => $node, 
        hiera_config => $hiera_config, 
        modulepath   => $modulepath
      )
    }
  }
}
