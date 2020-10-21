# = Function boltello_builder::fetch_ssh_key()
#
Puppet::Functions.create_function(:'boltello_builder::fetch_ssh_key') do
  dispatch :fetch_ssh_key do
    param 'Stdlib::Absolutepath', :path
  end

  def fetch_ssh_key(path)
    File.readlines(path)[0].split(/\s/)[1]
  end
end
