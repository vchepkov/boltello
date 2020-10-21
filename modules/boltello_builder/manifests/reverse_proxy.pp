# == Class boltello_builder::reverse_proxy
/*
katello server:
katello-certs-check -c /etc/puppetlabs/puppet/ssl/certs/$(hostname).pem \
-k /etc/puppetlabs/puppet/ssl/private_keys/$(hostname).pem \
-b /etc/puppetlabs/puppet/ssl/ca/ca_crt.pem
proxy server:
katello-certs-check -c /etc/puppetlabs/puppet/ssl/certs/$(hostname).pem \
-k /etc/puppetlabs/puppet/ssl/private_keys/$(hostname).pem \
-b /etc/puppetlabs/puppet/ssl/certs/ca.pem
openssl s_client -host <katello server fqdn> -port 8140 \
-cert /etc/puppetlabs/puppet/ssl/certs/$(hostname).pem \
-key /etc/puppetlabs/puppet/ssl/private_keys/$(hostname).pem \
-CAfile /var/lib/puppet/ssl/certs/ca.pem
*/
# 
class boltello_builder::reverse_proxy (
  Boolean $enable_remote_agent_install,
  String $conf_dir
){
  # Fail unless proxy.yaml is used
  unless $facts['boltello_role'] == 'proxy' {
    file { "${conf_dir}/sites-enabled/puppetserver-reverse-proxy.conf":
      ensure => absent,
      notify => Service['nginx'],
    }

    fail('Nginx only available with the proxy role. Remove the "botlello_builder::reverse_proxy" subclass from $classes')
  }

  include ::nginx

  if $enable_remote_agent_install {
    file { '/usr/share/nginx':
      ensure  => directory,
      require => Class['::nginx'],
    }

    file { '/usr/share/nginx/install':
      ensure  => present,
      require => File['/usr/share/nginx'],
      content => template('boltello_builder/install.erb'),
    }
  }
}
