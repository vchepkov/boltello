# = Plan boltello::foreman_proxy
#
plan boltello::foreman_proxy(
  TargetSpec $nodes = get_target('localhost')
){
  $enable_remote_execution = lookup('boltello::enable_remote_execution')
  $ssh_identity_dir        = lookup('boltello::ssh_identity_dir')
  $ssh_identity_file       = lookup('boltello::ssh_identity_file')
  $foreman_proxy_dir       = lookup('boltello::foreman_proxy_dir')
  $katello_server          = lookup('boltello::katello_server')

  # Ensure user
  run_command("/bin/id foreman-proxy 2> /dev/null || /sbin/adduser foreman-proxy -m --home-dir ${foreman_proxy_dir} -s /sbin/nologin",
    $nodes,
    'ensure foreman-proxy user',
    _catch_errors => true
  )

  # Ensure group
  run_command("/bin/getent group foreman-proxy 2> /dev/null || /sbin/groupadd foreman-proxy",
    $nodes,
    'ensure foreman-proxy group',
    _catch_errors => true
  )

  # Ensure user in group
  run_command('/usr/sbin/usermod -a -G foreman-proxy foreman-proxy',
    $nodes,
    'ensure foreman-proxy user in group',
    _catch_errors => true
  )

  if $enable_remote_execution {    
    get_targets($nodes).each |TargetSpec $node| {
      $check_ssh_identity_file = run_command("/bin/test -f ${ssh_identity_dir}/${ssh_identity_file}",
        $node,
        'check for ssh identity file',
        _catch_errors => true,
      )

      if !$check_ssh_identity_file.ok {
        # Ensure directory
        run_command("/bin/mkdir -p ${ssh_identity_dir}",
          $node,
          'ensure ssh identity directory',
        )
        # Ensure key
        run_command("/bin/ssh-keygen -f ${ssh_identity_dir}/${ssh_identity_file} -N '' -C foreman-proxy@${node.name} -m pem",
          $node,
          'ensure foreman-proxy keypair',
        )
      }

      # Get the key field
      $fetch_public_key = run_command("/bin/cat ${ssh_identity_dir}/${ssh_identity_file}.pub | cut -d ' ' -f2",
        get_target($katello_server),
        'fetch master public key',
      )

      $public_key_field = $fetch_public_key.first.value['stdout'].strip()

      $ssh_key_boltello = "/bin/grep ${public_key_field} /etc/puppetlabs/facter/facts.d/boltello_facts.yaml"
      $boltello_ssh_key = "/bin/echo \"boltello_ssh_key: '${public_key_field}'\" >> /etc/puppetlabs/facter/facts.d/boltello_facts.yaml"

      # Stuff the public key field in a facter fact to be retrieved by ssh_authorized_keys
      run_command("$ssh_key_boltello || $boltello_ssh_key",
        $node,
        'ensure boltello_ssh_key fact'
      )
    }

    # Ensure ownership
    run_command("/bin/chown -R foreman-proxy ${ssh_identity_dir}",
      $nodes,
      'ensure permissions on ssh identity directory',
    )
  }
}
