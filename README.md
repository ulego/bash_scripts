* wireguard.sh
  script for connecting to wireguard. During its work, it checks the geolocation of the network interface, and also when connecting - the wireguard interface and compares them
  has a trick - ping to wireguard before connecting
  run without arguments but change variables WIREGUARD_DIRECTORY and WIREGUARD_CONFIG in USER SETTING block
 requrements:
  ip jq sudo dhclient awk grep cut xargs timeout ping nping wg-quick curl systemctl systemd-resolved dhclient 
