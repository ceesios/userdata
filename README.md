# Userdata
Userdata scripts to customize cloud instances, also called Customization Scripts.

These scripts can be used on any cloud provider like AWS or OpenStack providers such as the dutch provider, CloudVPS.

# Usage
## Openstack
Reference the userdata script of your choice in Horizon when creating instances or via the cli:
~~~
openstack server create \
--image "$image" \
--flavor $flavor \
--security-group "$security-group" \
--key-name "$keyname" \
--nic net-id=$network \
--user-data ./$userdatascript \
$servername
~~~

## AWS


## Author

- [Cees Moerkerken](https://virtu-on.nl)
