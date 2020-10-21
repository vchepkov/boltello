# == Class boltello_builder::foreman_proxy
#
class boltello_builder::foreman_proxy (
  Boolean $enable_remote_execution,
  String $katello_server,
  String $foreman_proxy_dir,
  String $ssh_identity_dir,
  String $ssh_identity_file,
){
  include ::foreman_proxy

  $proxy_server = $facts['networking']['fqdn']

  if $enable_remote_execution {
    include ::foreman_proxy::plugin::remote_execution::ssh

    Exec {
      require => Class['::foreman_proxy::plugin::remote_execution::ssh'],
    }

    exec { 'ensure_ssh_identity_dirs':
      command => "/bin/mkdir -p {'${ssh_identity_dir}','${foreman_proxy_dir}'} && /bin/chown foreman-proxy:foreman-proxy {'${ssh_identity_dir}','${foreman_proxy_dir}'}",
      creates => "${ssh_identity_dir}",
    }

    file { 'ensure_ssh_hidden_dir':
      path    => "${foreman_proxy_dir}/.ssh",
      ensure  => link,
      target  => "${ssh_identity_dir}",
      notify  => Exec['restorecon_ssh_hidden_dir'],
      require => Exec['ensure_ssh_identity_dirs'],
    }

    file { 'ensure_foreman_proxy_private_key':
      path    => "${ssh_identity_dir}/${ssh_identity_file}",
      ensure  => present,
      require => File['ensure_ssh_hidden_dir'],
    }

    file { 'ensure_foreman_proxy_public_key':
      path    => "${ssh_identity_dir}/${ssh_identity_file}.pub",
      ensure  => present,
      require => File['ensure_foreman_proxy_private_key'],
    }

    exec { 'restorecon_ssh_hidden_dir':
      command     => "/sbin/restorecon -RvF ${foreman_proxy_dir}/.ssh",
      refreshonly => true,
      require     => File['ensure_foreman_proxy_public_key'],
    }

    if $proxy_server != $katello_server {
      # This node's public key
      ssh_authorized_key { "foreman-proxy@${proxy_server}":
        ensure => present,
        name    => "foreman-proxy@${proxy_server}",
        user    => 'root',
        type    => 'ssh-rsa',
        key     => boltello_builder::fetch_ssh_key("${ssh_identity_dir}/${ssh_identity_file}.pub"),
        require => Exec['restorecon_ssh_hidden_dir'],
        notify  => Service['foreman-proxy'],
      }
    }

    # Katello server public key
    ssh_authorized_key { "foreman-proxy@${katello_server}":
      ensure  => present,
      name    => "foreman-proxy@${katello_server}",
      user    => 'root',
      type    => 'ssh-rsa',
      key     => $facts['boltello_ssh_key'],
      require => Exec['restorecon_ssh_hidden_dir'],
      notify  => Service['foreman-proxy'],
    }
  }
}
