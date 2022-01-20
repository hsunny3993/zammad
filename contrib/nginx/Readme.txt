########### SELinux and Firewall setup
$ # Allow nginx or apache to access public files of Zammad and communicate
$ chcon -Rv --type=httpd_sys_content_t /opt/zammad/public/
$ chcon -Rv --type=httpd_sys_content_t /opt/zammad/storage/
$ setsebool httpd_can_network_connect on -P
$ semanage fcontext -a -t httpd_sys_content_t /opt/zammad/public/
$ semanage fcontext -a -t httpd_sys_content_t /opt/zammad/storage/
$ restorecon -Rv /opt/zammad/public/
$ restorecon -Rv /opt/zammad/storage/
$ chmod -R a+r /opt/zammad/public/
$ chmod -R a+r /opt/zammad/storage/

########## Nginx permission
chown -Rf zammad:zammad /var/lib/nginx
chmod -Rf 755 /var/lib/nginx
certbot --nginx

########## Register service and port into /etc/services
firewall-cmd --add-service=postgresql --permanent
firewall-cmd --reload

########## Prevent timeout from `systemd service start`
https://sleeplessbeastie.eu/2020/02/29/how-to-prevent-systemd-service-start-operation-from-timing-out/


