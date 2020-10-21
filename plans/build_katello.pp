# == Plan boltello::build_katello
#
plan boltello::build_katello(
  TargetSpec $nodes               = get_target('katello'),
  String[1] $boltdir              = boltello::get_boltdir(),
  String[1] $modulepath           = "$boltdir/modules",
  String[1] $hiera_config         = "$boltdir/hiera.yaml",
  Optional[Boolean] $apply_noop   = false,
  Optional[Boolean] $force        = false,
  Optional[Boolean] $puppet_certs = true,
  Optional[String] $role_override = undef,
  Boolean $agent_only             = false,
  Boolean $katello_prep           = false,
  Boolean $monolithic             = false,
) {
  # Ensure command line options are mutually exclusive
  $build_stages   = [$agent_only, $katello_prep, $monolithic]
  $enabled_stages = $build_stages.filter |Boolean $value| { $value == true }
  
  if $enabled_stages.size > 1 {
    fail_plan('command line options are mutually exclusive')
  } elsif get_target($nodes).name != get_target('katello').name {
    fail_plan('ensure the target node is in the katello group')
  }

  # Iterate upon a single node to facilitate graceful exits with next()
  get_target($nodes).with |TargetSpec $node| {

    # Check installed version
    $check_version = run_plan('boltello::check_version', 
      nodes => $node, 
      force  => $force,
      caller => 'plan',
    )

    # Shift to next node if katello is installed and force not enabled
    if $check_version { next() }

    # Install puppet agent
    run_plan('boltello::install_puppet', 
      nodes         => $node, 
      boltdir       => $boltdir, 
      manage_config => true
    )

    if $agent_only { 
      warning("Advisory: puppet agent package installed")
      next()  
    }

    $boltello_role = $role_override.empty() ? { 
      true    => 'katello',
      default => file::exists("${boltdir}/data/roles/${role_override}.yaml") ? {
        true  => $role_override,
        false => 'katello'
      }
    }

    # Ensure the boltello_role fact for the katello server
    run_task('boltello::boltello_role', 
      $node, 
      "ensure fact boltello_role => ${boltello_role}",
      boltello_role => "${boltello_role}"
    )

    # Prep node with katello repositories/packages
    run_plan('boltello::katello_prep', 
      nodes => $node,
      force => ($katello_prep and $force)
    )

    # Lock packages
    run_plan('boltello::versionlock',
      nodes       => $nodes,
      lock_status => 'locked',
    )

    if $katello_prep {
      warning("Advisory: katello packages ensured")
      next() 
    }

    # Configure foreman-proxy user, facts, directories, keys
    run_plan('boltello::foreman_proxy',
      $node,
      _catch_errors => true
    )

    # Run puppet on the katello server
    $run_puppet = run_plan('boltello::run_puppet', 
      nodes        => $node, 
      hiera_config => $hiera_config, 
      modulepath   => $modulepath,
      apply_noop   => $apply_noop,
    )

    if !$monolithic { 
      $deployment_type = 'primary' 

      # Recursively copy the boltdir to be served by puppet
      run_plan('boltello::configure_directories', 
        katello => $node, 
        boltdir => $boltdir,
      )

      # Turn off Puppet certificate generation if default role is loaded from the command line
      # This is done for capsule-flavored servers which have their own CA built in
      $puppet_certs_ = ($boltello_role == 'katello' and $role_override.empty()) or $puppet_certs

      # Generate katello & puppet certificates for each proxy server
      run_plan('boltello::generate_certs', 
        katello      => $node, 
        boltdir      => $boltdir, 
        puppet_certs => $puppet_certs_
      )
    } else {
      $deployment_type = 'monolithic' 
    }

    if $run_puppet {
      warning("Advisory: katello $deployment_type server configuration complete")
    } else {
      err("Critical: katello $deployment_type server configuration failed")
    }
  }
}
