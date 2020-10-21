# == Plan boltello::run_puppet
#
plan boltello::run_puppet(
  TargetSpec $nodes,
  Optional[String] $boltdir      = boltello::get_boltdir(),
  String[1] $hiera_config        = "$boltdir/hiera.yaml",
  String[1] $modulepath          = "$boltdir/modules",
  Optional[String] $log_level    = 'debug',
  Optional[String] $logdest      = "$boltdir/puppet_debug.log",
  Optional[Boolean] $apply_noop  = false
) {
  $noop = $apply_noop ? {
    true  => '--noop',
    false => ''
  }

  $puppet_apply = '/opt/puppetlabs/bin/puppet apply'
  $args = "-e 'include boltello_builder' --hiera_config ${hiera_config} --modulepath ${modulepath} ${noop} --${log_level} --logdest ${logdest}"

  # Touch logdest
  run_command("/bin/touch $logdest",
    $nodes, 
    'ensure puppet debug log file',
  )

  # Run puppet apply 
  $apply_puppet = run_command("${puppet_apply} ${args}",
    $nodes,
    'puppet apply boltello_builder',
    _catch_errors => true
  )
  
  return $apply_puppet.ok
}
