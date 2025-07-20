# wireguard.sh
  Script for connecting to wireguard.  
  During its work, it checks the geolocation of the network interface, and also when connecting - the wireguard interface and compares them  
  Has a trick - ping to wireguard before connecting  
  Run without arguments but change variables **WIREGUARD_DIRECTORY** and **WIREGUARD_CONFIG** in USER SETTING block  
 ## requrements:
  ip jq sudo dhclient awk grep cut xargs timeout ping nping wg-quick curl systemctl systemd-resolved dhclient 
## warning
if system have more than one NIC with internet script choose NIC for WG randomly or you can type NIC name there: ```NIC=$(ls -l /sys/class/net/ | grep devices | grep -v virtual | awk -F "/" '{print $NF}')``` -> ```NIC=eth0```
