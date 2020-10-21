# Task boltello::remove_packages
#
#!/usr/bin/env bash
#
packages=$PT_packages
packages=($(echo $packages))

# Check for package and remove if present
for package in "${packages[@]}"; do
    [[ $(rpm -q $package) ]] && /bin/yum -y remove $package > /dev/null 2>&1
done

 
