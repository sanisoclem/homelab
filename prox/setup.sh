# reduce wearout on SSDs, remove on adding HA
systemctl stop corosync pve-ha-crm pve-ha-lrm 
systemctl disable corosync pve-ha-crm pve-ha-lrm 