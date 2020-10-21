# == Plan: boltello::update_metadata
#
plan boltello::update_metadata(
  TargetSpec $katello,
  String $boltdir = boltello::get_boltdir(),
  Pattern[/^[-+]?[0-9]*\.?[0-9]+$/] $katello_version,
  Pattern[/^[-+]?[0-9]*\.?[0-9]+$/] $foreman_version
) {
  apply($katello, _catch_errors => true, _description => 'ensure boltello project metadata versions') {
    file_line { 'set foreman_version':
      path  => "${boltdir}/data/plans/common.yaml",
      line  => "'boltello::foreman_version': '${foreman_version}'",
      match => "'boltello::foreman_version':",
    }

    file_line { 'set katello_version':
      path  => "${boltdir}/data/plans/aliases.yaml",
      line  => "'boltello::katello_version': '${katello_version}'",
      match => "'boltello::katello_version':",
    }
  }
}
